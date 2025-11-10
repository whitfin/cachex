defmodule Cachex.Router do
  @moduledoc """
  Module controlling routing behaviour definitions.

  This module defines the router implementations for Cachex, allowing the user
  to route commands between nodes in a cache cluster. This means that users
  can provide their own routing and rebalancing logic without having to depend
  on it being included in Cachex.
  """
  alias Cachex.Router
  alias Cachex.Services

  # add some service aliases
  alias Services.Informant
  alias Services.Overseer

  # import macro stuff
  import Cachex.Error
  import Cachex.Spec

  #############
  # Behaviour #
  #############

  @doc """
  Initialize a routing state for a cache.

  Please see all child implementations for supported options.
  """
  @callback init(cache :: Cachex.t(), options :: Keyword.t()) :: any

  @doc """
  Retrieve the list of nodes from a routing state.
  """
  @callback nodes(state :: any) :: [atom]

  @doc """
  Route a key to a node in a routing state.
  """
  @callback route(state :: any, key :: any) :: atom

  @doc """
  Create a child specification to back a routing state.
  """
  @callback children(cache :: Cachex.t(), options :: Keyword.t()) ::
              [Supervisor.child_spec()]

  ##################
  # Implementation #
  ##################

  @doc false
  defmacro __using__(_) do
    quote location: :keep, generated: true do
      @behaviour Cachex.Router

      @doc false
      def init(cache, options \\ []),
        do: nil

      @doc false
      def children(cache, options),
        do: []

      # state modifiers are overridable
      defoverridable init: 2, children: 2
    end
  end

  ##############
  # Public API #
  ##############

  @doc """
  Retrieve all currently connected nodes (including this one).
  """
  @spec connected() :: [atom]
  def connected(),
    do: [node() | :erlang.nodes(:connected)]

  @doc """
  Retrieve all routable nodes for a cache.
  """
  @spec nodes(cache :: Cachex.t()) :: {:ok, [atom]}
  def nodes(cache(router: router(module: module, state: state))),
    do: {:ok, module.nodes(state)}

  @doc """
  Executes a previously dispatched action..
  """
  # The first match short circuits local-only caches
  @spec route(Cachex.t(), atom, {atom, [any]}) :: any
  def route(cache(router: router(module: Router.Local)) = cache, module, call),
    do: route_local(cache, module, call)

  def route(cache() = cache, module, {_action, arguments} = call) do
    # all calls should have options
    options = List.last(arguments)

    # can force local node with local: true
    case Keyword.get(options, :local) do
      true -> route_local(cache, module, call)
      _any -> route_cluster(cache, module, call)
    end
  end

  @doc """
  Dispatches a call to an appropriate execution environment.

  This acts as a macro just to avoid the overhead of slicing up module
  names at runtime, when they can be guaranteed at compile time much
  more easily.
  """
  defmacro route(cache, {action, _arguments} = call) do
    # coveralls-ignore-start
    name =
      action
      |> Kernel.to_string()
      |> String.replace_trailing("?", "")
      |> Macro.camelize()

    module = :"Elixir.Cachex.Actions.#{name}"
    # coveralls-ignore-stop

    quote do
      Overseer.with(unquote(cache), fn cache ->
        Router.route(cache, unquote(module), unquote(call))
      end)
    end
  end

  ###############
  # Private API #
  ###############

  # Results merging for distributed cache results.
  #
  # Follows these rules:
  #
  # - Lists are always concatenated.
  # - Numbers are always summed.
  # - Booleans are always AND-ed.
  # - Maps are always merged (recursively).
  #
  # This has to be public due to scopes, but we hide the docs
  # because we don't really care for anybody else calling it.
  defp result_merge(left, right) when is_list(left),
    do: left ++ right

  defp result_merge(left, right) when is_number(left),
    do: left + right

  defp result_merge(left, right) when is_boolean(left),
    do: left && right

  # coveralls-ignore-start
  defp result_merge(left, right) when is_map(left) do
    Map.merge(left, right, fn _, left, right ->
      result_merge(left, right)
    end)
  end

  # coveralls-ignore-stop

  # Provides handling for local actions on this node.
  #
  # This will provide handling of notifications across hooks before and after
  # the execution of an action. This is taken from code formerly in the old
  # `Cachex.Actions` module, but has been moved here as it's more appropriate.
  #
  # If `notify` is set to false, notifications are disabled and the call is
  # simply executed as is. If `via` is provided, you can override the handle
  # passed to the hooks (useful for re-use of functions). An example of this
  # is `decr/4` which simply calls `incr/4` with `via: { :decr, arguments }`.
  defp route_local(cache, module, {_action, arguments} = call) do
    option = List.last(arguments)
    notify = Keyword.get(option, :notify, true)

    message =
      notify &&
        case option[:via] do
          msg when not is_tuple(msg) -> call
          msg -> msg
        end

    notify && Informant.broadcast(cache, message)
    result = apply(module, :execute, [cache | arguments])

    if notify do
      Informant.broadcast(
        cache,
        message,
        Keyword.get(option, :result, result)
      )
    end

    result
  end

  # actions based on a key
  @keyed_actions [
    :del,
    :exists?,
    :expire,
    :fetch,
    :get,
    :get_and_update,
    :incr,
    :invoke,
    :put,
    :refresh,
    :take,
    :touch,
    :ttl,
    :update
  ]

  # Provides handling to key-based actions distributed to remote nodes.
  #
  # The algorithm here is simple; hash the key and slot the value using JCH into
  # the total number of slots available (i.e. the count of the nodes). If it comes
  # out to the local node, just execute the local code, otherwise RPC the base call
  # to the remote node, and just assume that it'll correctly handle it.
  defp route_cluster(cache, module, {action, [key | _]} = call) when action in @keyed_actions do
    cache(router: router(module: router, state: nodes)) = cache
    route_node(cache, module, call, router.route(nodes, key))
  end

  # actions which merge outputs
  @merge_actions [
    :clear,
    :empty?,
    :export,
    :import,
    :keys,
    :purge,
    :reset,
    :size
  ]

  # Provides handling of cross-node actions distributed over remote nodes.
  #
  # This will do an RPC call across all nodes to fetch their results and merge
  # them with the results on the local node. The hooks will only be notified
  # on the local node, due to an annoying recursion issue when handling the
  # same across all nodes - seems to provide better logic though.
  defp route_cluster(cache, module, {action, arguments} = call) when action in @merge_actions do
    # fetch the nodes from the cluster state
    cache(router: router(module: router, state: state)) = cache

    # execution on the local node to combine
    result = route_local(cache, module, call)

    # execute the call on all other nodes
    {results, _} =
      state
      |> router.nodes()
      |> List.delete(node())
      |> :rpc.multicall(module, :execute, [cache | arguments])

    # run result merging to blend both sets
    Enum.reduce(results, result, &result_merge/2)
  end

  # actions which always run locally
  @local_actions [
    :inspect,
    :prune,
    :restore,
    :save,
    :stats,
    :warm
  ]

  # Provides handling of `:inspect` operations.
  #
  # These operations are guaranteed to run on the local nodes.
  defp route_cluster(cache, module, {action, _arguments} = call) when action in @local_actions,
    do: route_local(cache, module, call)

  # Provides handling of `:put_many` operations.
  #
  # These operations can only execute if their keys slot to the same remote nodes.
  defp route_cluster(cache, module, {:put_many, _arguments} = call),
    do: route_batch(cache, module, call, &elem(&1, 0))

  # Provides handling of `:transaction` operations.
  #
  # These operations can only execute if their keys slot to the same remote nodes.
  defp route_cluster(cache, module, {:transaction, [[] | _]} = call),
    do: route_local(cache, module, call)

  defp route_cluster(cache, module, {:transaction, [_keys | _]} = call),
    do: route_batch(cache, module, call, & &1)

  # Catch-all just in case we missed something...
  defp route_cluster(_cache, _module, _call),
    do: error(:non_distributed)

  # coveralls-ignore-stop

  # Calls a slot for the provided cache action if all keys slot to the same node.
  #
  # This is a delegate handler for `route_node/4`, but ensures that all keys slot to the
  # same node to avoid the case where we have to fork a call out internally.
  defp route_batch(cache, module, {_action, [keys | _]} = call, mapper) do
    # map all keys to a slot in the nodes list
    cache(router: router(module: router, state: state)) = cache
    slots = Enum.map(keys, &router.route(state, mapper.(&1)))

    # unique to avoid dups
    case Enum.uniq(slots) do
      # if there's a single slot it's safe to continue with the call to the remote
      [slot] ->
        route_node(cache, module, call, slot)

      # otherwise, cross_slot errors!
      _disable ->
        error(:cross_slot)
    end
  end

  # Calls a node for the provided cache action.
  #
  # This will determine a local slot and delegate locally if so, bypassing
  # any RPC calls in order to gain a slight bit of performance.
  defp route_node(cache(name: name) = cache, module, {action, arguments} = call, node) do
    here = node()

    case node do
      ^here ->
        route_local(cache, module, call)

      targeted ->
        result =
          :rpc.call(
            targeted,
            Cachex,
            action,
            [name | arguments]
          )

        with {:badrpc, reason} <- result do
          {:error, reason}
        end
    end
  end
end
