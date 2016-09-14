defmodule Cachex.Hook do
  @moduledoc false
  # This module defines the hook implementations for Cachex, allowing the user to
  # add hooks into the command execution. This means that users can build plugin
  # style listeners in order to do things like logging. Hooks can be registered
  # to execute either before or after the Cachex command, and can be blocking as
  # needed. You can also define that the results of the command are provided to
  # post-hooks, in case you wish to use the results in things such as log messages.

  # define our opaque type
  @opaque t :: %__MODULE__{ }

  # define our struct
  defstruct args: [],
            async: true,
            max_timeout: nil,
            module: nil,
            ref: nil,
            provide: [],
            results: false,
            server_args: [],
            type: :post

  @doc """
  Groups hooks by their execution type (pre/post).

  We use this to separate the execution phases in order to achieve a smaller
  iteration at later stages of execution (it saves a microsecond or so).
  """
  @spec group_by_type(hooks :: [ Hook.t ]) :: %{ pre: [Hook.t], post: [Hook.t] }
  def group_by_type(hooks) do
    hooks
    |> List.wrap
    |> Enum.group_by(fn
        (%__MODULE__{ "type": type }) -> type
        (_) -> nil
       end)
    |> Map.put_new(:pre, [])
    |> Map.put_new(:post, [])
  end
  def group_by_type(hooks, type) when type in [ :pre, :post ],
  do: group_by_type(hooks)[type]

  @doc """
  Handler for broadcasting a set of actions and results to all registered hooks.
  This is fired by out-of-proc calls (i.e. Janitors) which need to notify hooks.
  """
  def broadcast(cache, action, result) when is_atom(cache) do
    case Cachex.State.get(cache) do
      nil -> false
      val -> notify(val.post_hooks, action, result)
    end
  end

  @doc """
  Notifies a listener of the passed in data.

  If the data is a list, we convert it to a tuple in order to make it easier to
  pattern match against. We accept a list of listeners in order to allow for
  multiple (plugin style) listeners. Initially had the empty clause at the top
  but this way is better (at the very worst it's the same performance).
  """
  @spec notify(hooks :: [ Hook.t ], action :: { }, results :: { } | nil) :: true
  def notify(_hooks, _action, _results \\ nil)
  def notify([hook|tail], action, results) do
    emit(hook, action, results)
    notify(tail, action, results)
  end
  def notify([], _action, _results), do: true

  def validate(hooks) do
    hooks
    |> List.wrap
    |> do_validate([])
  end

  defp do_validate([ ], acc) do
    { :ok, Enum.reverse(acc) }
  end
  defp do_validate([ %__MODULE__{ module: mod } = hook | rest ], acc) do
    mod.__info__(:module)
    do_validate(rest, [ hook | acc ])
  rescue
    _ -> Cachex.Errors.invalid_hook()
  end
  defp do_validate([ _invalid | rest ], acc) do
    do_validate(rest, acc)
  end

  # Internal emission, used to define whether we send using an async request or
  # not. We also determine whether to pass the results back at this point or not.
  # This only happens for post-hooks, and if the results have been requested. We
  # skip the overhead in GenEvent and go straight to `send/2` to gain all speed
  # possible here.
  defp emit(hook, action, results) do
    cond do
      hook.ref == nil ->
        nil
      hook.results and hook.type == :post ->
        emit(hook, { action, results })
      true ->
        emit(hook, action)
    end
  end
  defp emit(%__MODULE__{ "async": true, "ref": ref }, payload) do
    send(ref, { :notify, { :async, payload } })
  end
  defp emit(%__MODULE__{ "async": false, "ref": ref } = hook, payload) do
    message_ref = :erlang.make_ref()

    send(ref, { :notify, { :sync, { self, message_ref }, payload } })

    receive do
      { :ack, ^ref, ^message_ref } -> nil
    after
      hook.max_timeout -> nil
    end
  end
  defp emit(_, _action), do: nil

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      # inherit GenEvent
      use GenEvent

      # force the Hook behaviours
      @behaviour Cachex.Hook.Behaviour

      @doc false
      def init(args) do
        {:ok, args}
      end

      @doc false
      def handle_notify(event, state) do
        {:ok, state}
      end

      @doc false
      def handle_notify(event, results, state) do
        {:ok, state}
      end

      @doc false
      def handle_event({ :async, event }, state),
      do: delegate_notify(event, state)
      def handle_event({ :sync, { ref, msg }, event }, state) do
        res = delegate_notify(event, state)
        send(ref, { :ack, self, msg })
        res
      end
      def handle_event({ :reset, args }, state),
      do: apply(__MODULE__, :init, args)
      def handle_event(_msg, state) do
        {:ok, state}
      end

      @doc false
      def handle_call(msg, state) do
        reason = { :bad_call, msg }
        case :erlang.phash2(1, 1) do
          0 -> exit(reason)
          1 -> { :remove_handler, reason }
        end
      end

      @doc false
      def handle_info(_msg, state) do
        {:ok, state}
      end

      @doc false
      def terminate(_reason, _state) do
        :ok
      end

      @doc false
      def code_change(_old, state, _extra) do
        {:ok, state}
      end

      # Internal function to simply delegate the message through to the override.
      # This is only needed because we want to pass the results as a separate
      # argument, rather than passing through a tuple of message and results.
      defp delegate_notify(event, state) do
        case event do
          { msg, result } when is_tuple(msg) and is_tuple(result) ->
            handle_notify(msg, result, state)
          other ->
            handle_notify(other, state)
        end
      end

      # Allow overrides of everything *except* the handle_event implementation.
      # We reserve that for internal use in order to make Hook definitions as
      # straightforward as possible.
      defoverridable [
        init: 1,
        handle_notify: 2,
        handle_notify: 3,
        handle_call: 2,
        handle_info: 2,
        terminate: 2,
        code_change: 3
      ]
    end
  end

end
