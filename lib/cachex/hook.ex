defmodule Cachex.Hook do
  @moduledoc false
  # This module defines the hook implementations for Cachex, allowing the user to
  # add hooks into the command execution. This means that users can build plugin
  # style listeners in order to do things like logging. Hooks can be registered
  # to execute either before or after the Cachex command, and can be blocking as
  # needed. You can also define that the results of the command are provided to
  # post-hooks, in case you wish to use the results in things such as log messages.

  defstruct async: true,
            module: nil,
            ref: nil,
            results: false,
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
        (%__MODULE__{ } = hook) ->
          hook
        (mod) when is_tuple(mod) ->
          apply(__MODULE__, :parse_hook, Tuple.to_list(mod))
        (mod) when is_list(mod) ->
          apply(__MODULE__, :parse_hook, mod)
        (_) ->
          nil
       end)
    |> Stream.map(&(start_hook/1))
    |> Stream.filter(&(&1 != nil))
    |> Enum.to_list
  end

  @doc """
  Takes a combination of args and coerces defaults for a listener. We default to a
  pre-hook, and async execution. I imagine this is the most common use case and so
  it makes the most sense to default to this. It can be overriden in the options,
  and should really always be explicit.
  """
  def parse_hook(_mod, _opts \\ [])
  def parse_hook(mod, opts) when not is_list(opts) do
    parse_hook(mod, [])
  end
  def parse_hook(mod, opts) do
    def_async = case opts[:async] do
      false -> false
      _true -> true
    end

    %__MODULE__{
      "async": def_async,
      "module": mod,
      "results": !!opts[:include_results],
      "type": case opts[:type] do
        :post -> :post
        _post -> :pre
      end
    }
  end

  @doc """
  Starts a listener. We check to ensure that the listener is a module before
  trying to start it and add as a handler. If anything goes wrong at this point
  we just nil the listener to avoid errors later.
  """
  def start_hook(%__MODULE__{ } = hook) do
    try do
      hook.module.__info__(:module)

      args = if is_atom(hook.ref) do
        [ name: hook.ref ]
      else
        []
      end

      pid = case GenEvent.start_link(args) do
        { :ok, pid } ->
          GenEvent.add_handler(pid, hook.module, [])
          pid
        { :error, { :already_started, pid } } ->
          pid
        _error -> nil
      end

      case pid do
        nil -> nil
        pid -> %__MODULE__{ hook | "ref": (args[:name] || pid) }
      end
    rescue
      _error -> nil
    end
  end
  def start_hook(_), do: nil

  @doc """
  Allows for finding a hook by the name of the module. This is only for convenience
  when trying to locate a potential Cachex.Stats hook.
  """
  def hook_by_module(hooks, module) when not is_list(hooks) do
    hook_by_module([hooks], module)
  end
  def hook_by_module([hook|tail], module) do
    case hook do
      %__MODULE__{ "module": ^module } -> hook
      _ -> hook_by_module(tail, module)
    end
  end
  def hook_by_module([], _module), do: nil

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
  def hooks_by_type(hooks, type) when not is_list(hooks) do
    hooks_by_type([hooks], type) 
  end
  def hooks_by_type(hooks, type) when type in [ :pre, :post ] do
    Enum.filter(hooks, fn
      (%__MODULE__{ "type": ^type }) -> true
      (_) -> false
    end)
  end

end
