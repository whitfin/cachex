defmodule Cachex.Hook do
  @moduledoc false
  # Module controlling hook behaviour definitions.
  #
  # This module defines the hook implementations for Cachex, allowing the user to
  # add hooks into the command execution. This means that users can build plugin
  # style listeners in order to do things like logging. Hooks can be registered
  # to execute either before or after the Cachex command, and can be blocking as
  # needed.

  @doc """
  Handles a cache notification.

  The first argument is the action being taken along with arguments, with the
  second argument being the results of the action (this can be nil for hooks)
  which fire before the action is executed.
  """
  @callback handle_notify(tuple, tuple, any) :: { :ok, any }

  @doc """
  Handles a provisioning call.

  The provided argument will be a Tuple dictating the type of value being
  provisioned along with the value itself. This can be used to listen on
  states required for hook executions (such as cache records).
  """
  @callback handle_provision({ atom, any }, any) :: { :ok, any }

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      # force the Hook behaviours
      @behaviour Cachex.Hook

      # inherit server
      use GenServer

      @doc false
      def init(args),
        do: { :ok, args }

      @doc false
      def handle_notify(event, result, state),
        do: { :ok, state }

      @doc false
      def handle_provision(provisions, state),
        do: { :ok, state }

      @doc false
      def handle_info({ :cachex_reset, args }, state) do
        { :ok, new_state } = apply(__MODULE__, :init, [ args ])
        { :noreply, new_state }
      end

      @doc false
      def handle_info({ :cachex_provision, provisions }, state) do
        { :ok, new_state } = handle_provision(provisions, state)
        { :noreply, new_state }
      end

      @doc false
      def handle_info({ :cachex_notify, { event, result } }, state) do
        { :ok, new_state } = handle_notify(event, result, state)
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

        case Task.yield(task, timeout) || Task.shutdown(task) do
          { :ok, { :ok, new_state } } ->
            { :reply, :ok, new_state }
          nil ->
            { :reply, :hook_timeout, state }
        end
      end

      # Allow overrides of everything *except* the handle_event implementation.
      # We reserve that for internal use in order to make Hook definitions as
      # straightforward as possible.
      defoverridable [
        init: 1,
        handle_notify: 3,
        handle_provision: 2
      ]
    end
  end
end
