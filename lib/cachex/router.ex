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

  # actions which don't notify hooks for some reason
  @quiet_actions [ :inspect, :reset, :stats, :transaction ]

  @doc """
  Dispatches a call to an appropriate execution environment.

  This acts as a macro just to avoid the overhead of slicing up module
  names are runtime, when they can be guaranteed at compile time much
  more easily.
  """
  defmacro dispatch(cache, { action, _arguments } = call) do
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
  defmacro execute(cache, module, call)

  # Quietly executes actions which do not broadcast.
  defmacro execute(cache, module, { action, arguments })
  when action in @quiet_actions do
    quote do
      apply(unquote(module),:execute,[ unquote(cache) | unquote(arguments) ])
    end
  end

  # Executes a cache action, broadcasting to all hooks.
  #
  # Hooks will be notified before and after the exection of the action. Rather
  # than relying on this being hand-written everywhere, this is automatically
  # injected to all dispatched actions at compile time to ensure that all cache
  # notifications will be handled automatically.
  defmacro execute(cache, module, { _action, arguments } = call) do
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
        results = Keyword.get(option, :hook_result, result)
        Informant.broadcast(unquote(cache), message, results)
      end

      result
    end
  end
end
