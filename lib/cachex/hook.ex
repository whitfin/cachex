defmodule Cachex.Hook do
  @moduledoc """
  Module controlling hook behaviour definitions.

  This module defines the hook implementations for Cachex, allowing the user to
  add hooks into the command execution. This means that users can build plugin
  style listeners in order to do things like logging. Hooks can be registered
  to execute either before or after the Cachex command, and can be blocking as
  needed.
  """
  import Cachex.Spec

  # types of accepted hooks
  @hook_types [:service, :post, :pre]

  #############
  # Behaviour #
  #############

  @doc """
  Returns the actions this hook is expected to listen on.

  This will default to an empty list, to force the developer to opt into the
  actions they receive notifications for. If all actions should be received,
  you can use the `:all` atom to receive everything.
  """
  @callback actions :: :all | [atom]

  @doc """
  Returns whether this hook is asynchronous or not.
  """
  @callback async? :: boolean

  @doc """
  Returns the timeout for all calls to this hook.

  This will be applied to hooks regardless of whether they're synchronous or
  not; a behaviour change which shipped in v3.0 initially.
  """
  @callback timeout :: nil | integer

  @doc """
  Returns the type of this hook.

  This should return `:post` to fire after a cache action has occurred, and
  return `:pre` if it should fire before the action occurs. The `:quiet` type
  is for hooks which don't listen to any broadcasts.
  """
  @callback type :: :pre | :post | :service

  @doc """
  Handles a cache notification.

  The first argument is the action being taken along with arguments, with the
  second argument being the results of the action (this can be nil for hooks)
  which fire before the action is executed.
  """
  @callback handle_notify(
              action :: {action :: atom, args :: list},
              result :: {status :: atom, value :: any},
              state :: any
            ) ::
              {:ok, any}

  ##################
  # Implementation #
  ##################

  @doc false
  defmacro __using__(_) do
    quote location: :keep, generated: true do
      # force the Hook behaviours
      @behaviour Cachex.Hook

      # inherit server
      use GenServer
      use Cachex.Provision

      @doc false
      def init(args),
        do: {:ok, args}

      @doc false
      def child_spec(args),
        do: super(args)

      # allow overriding of init
      defoverridable init: 1

      #################
      # Configuration #
      #################

      @doc false
      def actions,
        do: []

      @doc false
      def async?,
        do: true

      @doc false
      def timeout,
        do: nil

      @doc false
      def type do
        case actions() do
          [] -> :service
          _ -> :post
        end
      end

      # config overrides
      defoverridable actions: 0,
                     async?: 0,
                     timeout: 0,
                     type: 0

      #########################
      # Notification Handlers #
      #########################

      @doc false
      def handle_notify(event, result, state),
        do: {:ok, state}

      # listener override
      defoverridable handle_notify: 3

      ##########################
      # Private Implementation #
      ##########################

      @doc false
      def handle_info({:cachex_reset, args}, state) do
        {:ok, new_state} = init(args)
        {:noreply, new_state}
      end

      @doc false
      def handle_info({:cachex_notify, {event, result}}, state) do
        case timeout() do
          nil ->
            {:ok, new_state} = handle_notify(event, result, state)
            {:noreply, new_state}

          val ->
            task =
              Task.async(fn ->
                handle_notify(event, result, state)
              end)

            case Task.yield(task, val) || Task.shutdown(task) do
              {:ok, {:ok, new_state}} -> {:noreply, new_state}
              nil -> {:noreply, state}
            end
        end
      end

      @doc false
      def handle_call({:cachex_notify, _message} = message, _ctx, state) do
        {:noreply, new_state} = handle_info(message, state)
        {:reply, :ok, new_state}
      end
    end
  end

  ##############
  # Public API #
  ##############

  @doc """
  Concatenates all hooks in a cache.
  """
  @spec concat(Cachex.t() | Cachex.Spec.hooks()) :: [Cachex.Spec.hook()]
  def concat(hooks() = hooks) do
    @hook_types
    |> Enum.map(&for_type(hooks, &1))
    |> Enum.concat()
  end

  def concat(cache(hooks: hooks)),
    do: concat(hooks)

  @doc """
  Locates a hook module for a cache.
  """
  @spec locate(Cachex.t() | Cachex.Spec.hooks(), atom(), atom()) ::
          Cachex.Spec.hook() | nil
  def locate(hooks, module, type \\ :all)

  def locate(hooks() = hooks, module, type) do
    hooks
    |> concat()
    |> Enum.find(&match_hook(&1, module, type))
  end

  def locate(cache(hooks: hooks), module, type),
    do: locate(hooks, module, type)

  @doc """
  Retrieve all known types of hook.
  """
  def types(),
    do: @hook_types

  ###############
  # Private API #
  ###############

  # Hook lookup at runtime, instead of `hooks/2`.
  for type <- @hook_types do
    defp for_type(hooks() = hooks, unquote(type)),
      do: hooks(hooks, unquote(type))
  end

  # Find a hook based on module name and module type.
  defp match_hook(hook(module: module), module, :all),
    do: true

  defp match_hook(hook(module: module), module, type),
    do: module.type() == type

  defp match_hook(_hook, _module, _type),
    do: false
end
