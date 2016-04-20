defmodule Cachex.Hook do
  # require the Logger
  require Logger

  @moduledoc false
  # This module defines the hook implementations for Cachex, allowing the user to
  # add hooks into the command execution. This means that users can build plugin
  # style listeners in order to do things like logging. Hooks can be registered
  # to execute either before or after the Cachex command, and can be blocking as
  # needed. You can also define that the results of the command are provided to
  # post-hooks, in case you wish to use the results in things such as log messages.

  defstruct args: [],
            async: true,
            max_timeout: 5,
            module: nil,
            ref: nil,
            provide: [],
            results: false,
            server_args: [],
            type: :pre

  @doc """
  Starts any required listeners. We allow either a list of listeners, or a single
  listener (a user can attach N listeners as plugins). We take all listeners and
  convert them into a parsed hook, and then start all the hooks in processes which
  allows async listening.
  """
  def initialize_hooks(mod) when not is_list(mod), do: initialize_hooks([mod])
  def initialize_hooks(mods) when is_list(mods) do
    mods
    |> Stream.map(fn
        (%__MODULE__{ } = hook) -> hook
        (_) -> nil
       end)
    |> Stream.map(&(start_hook/1))
    |> Stream.filter(&(&1 != nil))
    |> Enum.to_list
  end

  # Starts a listener. We check to ensure that the listener is a module before
  # trying to start it and add as a handler. If anything goes wrong at this point
  # we just nil the listener to avoid errors later.
  defp start_hook(%__MODULE__{ } = hook) do
    try do
      hook.module.__info__(:module)

      pid = case GenEvent.start_link(hook.server_args) do
        { :ok, pid } ->
          GenEvent.add_handler(pid, hook.module, hook.args)
          pid
        { :error, { :already_started, pid } } ->
          Logger.warn(fn ->
            "Unable to assign hook (server already assigned): #{hook.module}"
          end)
          pid
        _error -> nil
      end

      case pid do
        nil -> nil
        pid -> %__MODULE__{ hook | "ref": pid }
      end
    rescue
      e ->
        Logger.warn(fn ->
          """
          Unable to assign hook (uncaught error): #{inspect(e)}
          #{Exception.format_stacktrace(System.stacktrace())}
          """
        end)
        nil
    end
  end
  defp start_hook(_), do: nil

  @doc """
  Allows for finding a hook by the name of the module. This is only for convenience
  when trying to locate a potential Cachex.Stats hook.
  """
  def hook_by_module(hooks, module) do
    hooks
    |> List.wrap
    |> Enum.find(nil, fn
        (%__MODULE__{ "module": ^module }) -> true
        (_) -> false
       end)
  end

  @doc """
  Simple shorthanding for pulling the ref of a hook which is found by module. This
  is again just for convenience when finding the Cachex.Stats hooks.
  """
  def ref_by_module(hooks, module) do
    case hook_by_module(hooks, module) do
      nil -> nil
      mod -> mod.ref
    end
  end

  @doc """
  Groups hooks by their execution type (pre/post). We use this to separate the
  execution phases in order to achieve a smaller iteration at later stages of
  execution (it saves a microsecond or so).
  """
  def hooks_by_type(hooks, type) when type in [ :pre, :post ] do
    hooks
    |> List.wrap
    |> Enum.filter(fn
        (%__MODULE__{ "type": ^type }) -> true
        (_) -> false
       end)
  end

  @doc """
  Calls a hook instance with the specified message and timeout.
  """
  def call(%__MODULE__{ module: mod, ref: ref }, msg, timeout \\ 5000),
  do: GenEvent.call(ref, mod, msg, timeout)

  @doc """
  Provides a single point to call to provision all hooks. We forward the message
  on to the hook ref.
  """
  def provision(%__MODULE__{ } = hook, msg),
  do: __MODULE__.send(hook, { :provision, msg })

  @doc """
  Delivers a message to the specified hook.
  """
  def send(%__MODULE__{ ref: ref }, msg),
  do: Kernel.send(ref, msg)

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
