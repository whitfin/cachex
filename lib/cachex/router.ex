defmodule Cachex.Router do
  @moduledoc """
  Routing module to dispatch Cachex actions to their execution environment.

  This module acts as the single source of dispatch within Cachex. In prior
  versions the backing actions were called directly from the main interface
  and were wrapped in macros, which was difficult to maintain and also quite
  noisy. Now that all execution flows via the router, this is no longer an
  issue and it also serves as a gateway to distribution in the future.
  """
  alias Cachex.Router
  alias Cachex.Services

  # add some service aliases
  alias Services.Informant
  alias Services.Overseer

  # import macro stuff
  import Cachex.Errors
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Dispatches a call to an appropriate execution environment.

  This acts as a macro just to avoid the overhead of slicing up module
  names are runtime, when they can be guaranteed at compile time much
  more easily.
  """
  defmacro call(cache, { action, _arguments } = call) do
    act_name =
      action
      |> Kernel.to_string
      |> String.replace_trailing("?", "")
      |> Macro.camelize

    act_join = :"Elixir.Cachex.Actions.#{act_name}"

    quote do
      Overseer.enforce(unquote(cache)) do
        Router.execute(var!(cache), unquote(act_join), unquote(call))
      end
    end
  end

  @doc """
  Executes a previously dispatched action.

  This macro should not be called externally; the only reason it remains
  public is due to the code injected by the `dispatch/2` macro.
  """
  defmacro execute(cache, module, call) do
    quote do
      current = node()
      case unquote(cache) do
        cache(nodes: [ ^current ]) ->
          unquote(configure_local(cache, module, call))
        cache(nodes: remote_nodes) ->
          unquote(configure_remote(cache, module, call, quote(do: remote_nodes)))
      end
    end
  end

  ###############
  # Private API #
  ###############

  # Provides handling for local actions on this node.
  #
  # This will provide handling of notifications across hooks before and after
  # the execution of an action. This is taken from code formerly in the old
  # `Cachex.Actions` module, but has been moved here as it's more appopriate.
  #
  # If `notify` is set to false, notifications are disabled and the call is
  # simply executed as is. If `via` is provided, you can override the handle
  # passed to the hooks (useful for re-use of functions). An example of this
  # is `decr/4` which simply calls `incr/4` with `via: { :decr, arguments }`.
  defp configure_local(cache, module, { _action, arguments } = call) do
    quote do
      option = List.last(unquote(arguments))
      notify = Keyword.get(option, :notify, true)

      message = notify && case option[:via] do
        msg when not is_tuple(msg) -> unquote(call)
        msg -> msg
      end

      notify && Informant.broadcast(unquote(cache), message)
      result = apply(unquote(module), :execute, [ unquote(cache) | unquote(arguments) ])

      if notify do
        Informant.broadcast(
          unquote(cache),
          message,
          Keyword.get(option, :hook_result, result)
        )
      end

      result
    end
  end

  # actions based on a key
  @keyed_actions [
    :del,   :exists?, :expire,  :fetch,   :get,   :get_and_update,
    :incr,  :invoke,  :put,     :refresh, :take,  :touch,
    :ttl,   :update
  ]

  # Provides handling to key-based actions distributed to remote nodes.
  #
  # The algorithm here is simple; hash the key and slot the value using JCH into
  # the total number of slots available (i.e. the count of the nodes). If it comes
  # out to the local node, just execute the local code, otherwise RPC the base call
  # to the remote node, and just assume that it'll correctly handle it.
  defp configure_remote(cache, module, { action, [ key | _ ] } = call, nodes)
  when action in @keyed_actions do
    quote do
      unquote(call_slot(cache, module, call, nodes, slot_key(key, nodes)))
    end
  end

  # actions which merge outputs
  @merge_actions [
    :clear, :count, :empty?,  :export,
    :keys,  :purge, :reset,   :size,
    :stats
  ]

  # Provides handling of cross-node actions distributed over remote nodes.
  #
  # This will do an RPC call across all nodes to fetch their results and merge
  # them with the results on the local node. The hooks will only be notified
  # on the local node, due to an annoying recursion issue when handling the
  # same across all nodes - seems to provide better logic though.
  defp configure_remote(cache, module, { action, arguments } = call, nodes)
  when action in @merge_actions do
    quote do
      # all calls have options we can use
      options = List.last(unquote(arguments))

      results =
        # can force local node setting local: true
        case Keyword.get(options, :local) do
          true -> []
          _any ->
            # don't want to execute on the local node
            other_nodes = List.delete(unquote(nodes), node())

            # execute the call on all other nodes
            { results, _ } = :rpc.multicall(
              other_nodes,
              unquote(module),
              :execute,
              [ unquote(cache) | unquote(arguments) ]
            )

            results
        end

      # execution on the local node, using the local macros and then unpack
      { :ok, result } = (unquote(configure_local(cache, module, call)))

      # results merge
      merge_result =
        results
        |> Enum.map(&elem(&1, 1))
        |> Enum.reduce(result, fn
            # lists are always joined up
            (result, acc) when is_list(acc) ->
              acc ++ result

            # numbers are always summed
            (result, acc) when is_number(acc) ->
              acc + result

            # booleans are just and-ed
            (result, acc) when is_boolean(acc) ->
              acc && result

            # maps are always merged
            (result, acc) when is_map(acc) ->
              Map.merge(acc, result)
          end)

      # return after merge
      { :ok, merge_result }
    end
  end

  # actions which always run locally
  @local_actions [ :dump, :inspect, :load ]

  # Provides handling of `:inspect` operations.
  #
  # These operations are guaranteed to run on the local nodes.
  defp configure_remote(cache, module, { action, _arguments } = call, _nodes)
  when action in @local_actions,
    do: configure_local(cache, module, call)

  # Provides handling of `:put_many` operations.
  #
  # These operations can only execute if their keys slot to the same remote nodes.
  defp configure_remote(cache, module, { :put_many, _arguments } = call, nodes),
    do: multi_call_slot(cache, module, call, nodes, quote(do: &elem(&1, 0)))

  # Provides handling of `:transaction` operations.
  #
  # These operations can only execute if their keys slot to the same remote nodes.
  defp configure_remote(cache, module, { :transaction, [ keys | _ ] } = call, nodes) do
    case keys do
      [] -> configure_local(cache, module, call)
      __ -> multi_call_slot(cache, module, call, nodes, quote(do: &(&1)))
    end
  end

  # Any other actions are explicitly disabled in distributed environments.
  defp configure_remote(_cache, _module, _call, _nodes),
    do: error(:non_distributed)

  # Calls a slot for the provided cache action.
  #
  # This will determine a local slot and delegate locally if so, bypassing
  # any RPC calls required. This function currently assumes that there is
  # a local variable available named "remote_nodes" and "slot", until I
  # figure out how to better improve the macro scoping in use locally.
  defp call_slot(cache, module, { action, arguments } = call, nodes, slot) do
    quote do
      case Enum.at(unquote(nodes), unquote(slot)) do
        ^current ->
          unquote(configure_local(cache, module, call))

        targeted ->
          result = :rpc.call(
            targeted,
            Cachex,
            unquote(action),
            [ cache(unquote(cache), :name) | unquote(arguments) ]
          )

          with { :badrpc, reason } <- result do
            { :error, reason }
          end
      end
    end
  end

  # Calls a slot for the provided cache action if all keys slot to the same node.
  #
  # This is a delegate handler for `call_slot/5`, but ensures that all keys slot to the
  # same node to avoid the case where we have to fork a call out internally.
  defp multi_call_slot(cache, module, { _action, [ keys | _ ] } = call, nodes, mapper) do
    quote do
      # map all keys to a slot in the nodes list
      slots = Enum.map(unquote(keys), fn(key) ->
        # basically just slot_key(mapper.(key), nodes)
        unquote(slot_key(quote(do: unquote(mapper).(key)), nodes))
      end)

      # unique to avoid dups
      case Enum.uniq(slots) do
        # if there's a single slot it's safe to continue with the call to the remote
        [ slot ] -> unquote(call_slot(cache, module, call, nodes, quote(do: slot)))

        # otherwise, cross_slot errors!
        _disable -> error(:cross_slot)
      end
    end
  end

  # Slots a key into the list of provided nodes.
  #
  # This uses `:erlang.phash2/1` to hash the key to a numeric value,
  # as keys can be basically any type - so others hashes would be
  # more expensive due to the serialization costs. Note that the
  # collision possibility isn't really relevant, as long as there's
  # a uniformly random collision possibility.
  defp slot_key(key, nodes) do
    quote do
      unquote(key)
      |> :erlang.phash2
      |> Jumper.slot(length(unquote(nodes)))
    end
  end
end
