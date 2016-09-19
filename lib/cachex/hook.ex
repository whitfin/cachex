defmodule Cachex.Hook do
  @moduledoc false
  # This module defines the hook implementations for Cachex, allowing the user to
  # add hooks into the command execution. This means that users can build plugin
  # style listeners in order to do things like logging. Hooks can be registered
  # to execute either before or after the Cachex command, and can be blocking as
  # needed.

  # use our constants
  use Cachex.Constants

  # add some aliases
  alias Cachex.State

  # define our opaque type
  @opaque t :: %__MODULE__{ }

  # define our struct
  defstruct args: [],           # args to provide to init/1
            async: true,        # whether to run async or not
            max_timeout: nil,   # a timeout to use against sync hooks
            module: nil,        # the backing module of the Hook
            ref: nil,           # the proc the hook lives in
            provide: [],        # things to provide to the hook
            server_args: [],    # arguments to pass to the hook server
            type: :post         # whether the hook runs before or after the action

  @doc """
  Broadcasts a custom message to all attached post hooks.

  This exists because there are a number of processes which need to submit their
  values into the hooks, but don't have their own state or an outdated state.

  It only makes sense to send to post_hooks because at this point the action has
  already taken effect on the cache.
  """
  def broadcast(cache, action, result) when is_atom(cache) do
    case State.get(cache) do
      nil -> false
      val -> notify(val.post_hooks, action, result)
    end
  end

  @doc """
  Groups hooks by their execution type (pre/post).

  We use this to separate the execution phases in order to achieve a smaller
  iteration at later stages of execution (it saves a microsecond or so).
  """
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

  @doc """
  Groups hooks by a given execution type.

  Internally we just use `group_by_type/1` and pluck the required type to avoid
  duplication of code here (it's not hit often).
  """
  def group_by_type(hooks, type) when type in [ :pre, :post ],
  do: group_by_type(hooks)[type]

  @doc """
  Notifies a listener of the passed in data.

  If the data is a list, we convert it to a tuple in order to make it easier to
  pattern match against. We accept a list of listeners in order to allow for
  multiple (plugin style) listeners. Initially had the empty clause at the top
  but this way is better (at the very worst it's the same performance).
  """
  @spec notify(hooks :: [ Hook.t ], action :: { }, results :: { } | nil) :: true
  def notify(hooks, action, result \\ nil)
  def notify([hook|tail], action, result) do
    do_notify(hook, { action, result })
    notify(tail, action, result)
  end
  def notify([], _action, _result), do: true

  # Internal emission, used to define whether we send using an async request or
  # not. We also determine whether to pass the results back at this point or not.
  # This only happens for post-hooks, and if the results have been requested. We
  # skip the overhead in GenEvent and go straight to `send/2` to gain all speed
  # possible here.
  defp do_notify(%__MODULE__{ ref: nil }, _event),
    do: nil
  defp do_notify(%__MODULE__{ async: true, ref: ref }, event),
    do: send(ref, { :notify, { :async, event } })
  defp do_notify(%__MODULE__{ max_timeout: timeout, ref: ref }, event) do
    msg_ref = :erlang.make_ref()

    send(ref, { :notify, { :sync, { self, msg_ref }, event } })

    receive do
      { :ack, ^ref, ^msg_ref } -> nil
    after
      (timeout || 5) -> nil
    end
  end

  @doc """
  Validates a set of Hooks.

  On successful validation, this returns a list of valid hooks against a Tuple
  tagged as ok. If any of the hooks are invalid, we halt and return an error in
  order to indicate the error to the user.
  """
  def validate(hooks) do
    hooks
    |> List.wrap
    |> do_validate([])
  end

  # Validates a list of Hooks. If a hook has a valid module backing it, it is
  # treated as valid (any crashes following are down to the user at that point).
  # If not, we return an error to halt the validation. To check for a valid module,
  # we just try to call `__info__/1` on the module.
  defp do_validate([ %__MODULE__{ module: mod } = hook | rest ], acc) do
    try do
      mod.__info__(:module)
      do_validate(rest, [ hook | acc ])
    rescue
      _ -> @error_invalid_hook
    end
  end
  defp do_validate([ _invalid | rest ], acc),
    do: do_validate(rest, acc)
  defp do_validate([ ], acc),
    do: { :ok, Enum.reverse(acc) }

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
      def handle_notify(event, results, state) do
        {:ok, state}
      end

      @doc false
      def handle_event({ :async, { event, result } }, state) do
        handle_notify(event, result, state)
      end
      def handle_event({ :sync, { ref, msg }, { event, result } }, state) do
        res = handle_notify(event, result, state)
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

      # Allow overrides of everything *except* the handle_event implementation.
      # We reserve that for internal use in order to make Hook definitions as
      # straightforward as possible.
      defoverridable [
        init: 1,
        handle_notify: 3,
        handle_call: 2,
        handle_info: 2,
        terminate: 2,
        code_change: 3
      ]
    end
  end

end
