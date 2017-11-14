defmodule Cachex.Hook do
  @moduledoc false
  # This module defines the hook implementations for Cachex, allowing the user to
  # add hooks into the command execution. This means that users can build plugin
  # style listeners in order to do things like logging. Hooks can be registered
  # to execute either before or after the Cachex command, and can be blocking as
  # needed.

  # use our constants
  use Cachex.Constants

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
  This implementation is the same as `handle_notify/2`, except we also provide
  the results of the action as the second argument. This is only called if the
  `results` key is set to a truthy value inside your Cachex.Hook struct.
  """
  @callback handle_notify(tuple, tuple, any) :: { :ok, any }

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      # inherit server
      use GenServer

      # force the Hook behaviours
      @behaviour Cachex.Hook

      @doc false
      def init(args) do
        { :ok, args }
      end

      @doc false
      def handle_notify(event, result, state) do
        { :ok, state }
      end

      @doc false
      def handle_cast({ :cachex_notify, { event, result } }, state) do
        { :ok, new_state } = handle_notify(event, result, state)
        { :noreply, new_state }
      end

      @doc false
      def handle_cast({ :cachex_reset, args }, state) do
        { :ok, new_state } = apply(__MODULE__, :init, args)
        { :noreply, new_state }
      end

      @doc false
      def handle_call({ :cachex_notify, { event, result } } = msg, _ctx, state) do
        { :ok, new_state } = handle_notify(event, result, state)
        { :reply, :ok, new_state }
      end

      @doc false
      def handle_call({ :cachex_notify, { event, result }, timeout } = msg, _ctx, state) do
        task = Task.async(fn ->
          handle_notify(event, result, state)
        end)

        case Task.yield(task, timeout) do
          { :ok, { :ok, new_state } } ->
            { :reply, :ok, new_state }
          _timeout ->
            Task.shutdown(task)
            { :reply, :hook_timeout, state }
        end
      end

      # Allow overrides of everything *except* the handle_event implementation.
      # We reserve that for internal use in order to make Hook definitions as
      # straightforward as possible.
      defoverridable [
        init: 1,
        handle_notify: 3
      ]
    end
  end

  @doc """
  Validates a set of Hooks.

  On successful validation, this returns a list of valid hooks against a Tuple
  tagged as ok. If any of the hooks are invalid, we halt and return an error in
  order to indicate the error to the user.
  """
  def validate(hooks) when is_list(hooks),
    do: do_validate(hooks, [])
  def validate(hook),
    do: do_validate([ hook ], [])

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
  defp do_validate([ _invalid | _rest ], _acc),
    do: @error_invalid_hook
  defp do_validate([ ], acc),
    do: { :ok, Enum.reverse(acc) }
end
