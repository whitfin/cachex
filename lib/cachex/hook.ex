defmodule Cachex.Hook do
  @moduledoc """
  Module controlling hook behaviour definitions.

  This module defines the hook implementations for Cachex, allowing the user to
  add hooks into the command execution. This means that users can build plugin
  style listeners in order to do things like logging. Hooks can be registered
  to execute either before or after the Cachex command, and can be blocking as
  needed.
  """

  #############
  # Behaviour #
  #############

  @doc """
  Returns the actions this hook is expected to listen on.

  This will default to the atom `:all`, which signals that all actions should
  be reported to the hook. If not this atom, an enumerable of atoms should be
  returned.
  """
  @callback actions :: :all | [ atom ]

  @doc """
  Returns whether this hook is asynchronous or not.
  """
  @callback async? :: boolean

  @doc """
  Returns an enumerable of provisions this hook requires.

  The current provisions available to a hook are:

    * `cache` - a cache instance used to make cache calls from inside a hook
      with zero overhead.

  This should always return an enumerable of atoms; in the case of no required
  provisions an empty enumerable should be returned.
  """
  @callback provisions :: [ atom ]

  @doc """
  Returns the timeout for all calls to this hook.

  This will be applied to hooks regardless of whether they're synchronous or
  not; a behaviour change which shipped in v3.0 initially.
  """
  @callback timeout :: nil | integer

  @doc """
  Returns the type of this hook.

  This should return `:post` to fire after a cache action has occurred, and
  return `:pre` if it should fire before the action occurs.
  """
  @callback type :: :pre | :post

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

  ##################
  # Implementation #
  ##################

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

      # allow overriding of init
      defoverridable [ init: 1 ]

      #################
      # Configuration #
      #################

      @doc false
      def actions,
        do: :all

      @doc false
      def async?,
        do: true

      @doc false
      def provisions,
        do: []

      @doc false
      def timeout,
        do: nil

      @doc false
      def type,
        do: :post

      # config overrides
      defoverridable [
        actions: 0,
        async?: 0,
        provisions: 0,
        timeout: 0,
        type: 0
      ]

      #########################
      # Notification Handlers #
      #########################

      @doc false
      def handle_notify(event, result, state),
        do: { :ok, state }

      @doc false
      def handle_provision(provisions, state),
        do: { :ok, state }

      # listener override
      defoverridable [
        handle_notify: 3,
        handle_provision: 2
      ]

      ##########################
      # Private Implementation #
      ##########################

      @doc false
      def handle_info({ :cachex_reset, args }, state) do
        { :ok, new_state } = init(args)
        { :noreply, new_state }
      end

      @doc false
      def handle_info({ :cachex_provision, provisions }, state) do
        { :ok, new_state } = handle_provision(provisions, state)
        { :noreply, new_state }
      end

      @doc false
      def handle_info({ :cachex_notify, { event, result } }, state) do
        case timeout() do
          nil ->
            { :ok, new_state } = handle_notify(event, result, state)
            { :noreply, new_state }
          val ->
            task = Task.async(fn ->
              handle_notify(event, result, state)
            end)

            case Task.yield(task, val) || Task.shutdown(task) do
              { :ok, { :ok, new_state } } -> { :noreply, state }
              nil -> { :noreply, state }
            end
        end
      end

      @doc false
      def handle_call({ :cachex_notify, _message } = message, _ctx, state) do
        { :noreply, new_state } = handle_info(message, state)
        { :reply, :ok, new_state }
      end
    end
  end
end
