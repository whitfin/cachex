defmodule Cachex.Hook do
  @moduledoc false
  # This module defines the hook implementations for Cachex, allowing the user to
  # add hooks into the command execution. This means that users can build plugin
  # style listeners in order to do things like logging. Hooks can be registered
  # to execute either before or after the Cachex command, and can be blocking as
  # needed.

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
        { :ok, new_state } = apply(__MODULE__, :init, [ args ])
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
      defoverridable [ init: 1, handle_notify: 3 ]
    end
  end
end
