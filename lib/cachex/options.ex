defmodule Cachex.Options do
  @moduledoc false
  # A container to ensure that all option parsing is done in a single location
  # to avoid accidentally getting mixed field names and values across the library.

  defstruct cache: nil,             # the name of the cache
            ets_opts: nil,          # any options to give to ETS
            default_fallback: nil,  # the default fallback implementation
            default_ttl: nil,       # any default ttl values to use
            fallback_args: nil,     # arguments to pass to a cache loader
            listeners: nil,         # any debug listeners (GenEvent)
            nodes: nil,             # a list of nodes to connect to
            record_stats: nil,      # if we should store stats
            remote: nil,            # are we using a remote implementation
            transactional: nil,     # use a transactional implementation
            ttl_interval: nil       # the ttl check interval

  @doc """
  Parses a list of input options to the fields we care about, setting things like
  defaults and verifying types. The output of this function should be a set of
  options that we can use blindly in other areas of the library. As such, this
  function has the potential to become a little messy - but that's okay, since
  it saves us trying to duplicate this logic all over the codebase.
  """
  def parse(options \\ []) do
    cache = case options[:name] do
      val when val == nil or not is_atom(val) ->
        raise "Cache name must be a valid atom!"
      val -> val
    end

    ets_opts = Keyword.get(options, :ets_opts, [
      { :read_concurrency, true },
      { :write_concurrency, true }
    ])

    default_ttl = parse_number_option(options, :default_ttl)

    default_interval = case (!!default_ttl) do
      true  -> 1000
      false -> nil
    end

    ttl_interval = case options[:ttl_interval] do
      nil -> default_interval
      val when not is_number(val) or val < 0 -> nil
      val -> val
    end

    default_fallback = case options[:default_fallback] do
      fun when is_function(fun) -> fun
      _fn -> nil
    end

    fallback_args = case options[:fallback_args] do
      args when not is_list(args) -> {}
      args -> Cachex.Util.list_to_tuple(args)
    end

    nodes = case options[:nodes] do
      nodes when not is_list(nodes) -> nil
      nodes -> nodes
    end

    listeners = case options[:listeners] do
      nil -> []
      mod -> start_listeners(mod)
    end

    %__MODULE__{
      "cache": cache,
      "ets_opts": ets_opts,
      "default_fallback": default_fallback,
      "default_ttl": default_ttl,
      "fallback_args": fallback_args,
      "listeners": listeners,
      "nodes": nodes,
      "record_stats": !!options[:record_stats],
      "remote": (nodes != nil && nodes != [node()] || !!options[:remote]),
      "transactional": !!options[:transactional],
      "ttl_interval": ttl_interval
    }
  end

  # Retrieves a field from the options as a number. Numbers must be strictly
  # positive for our uses, so if the value is not a number (or is less than 0)
  # we move to a default value. If no default is provided, we just nil the value.
  defp parse_number_option(options, key, default \\ nil) do
    case options[key] do
      val when not is_number(val) or val < 1 -> default
      val -> val
    end
  end

  # Takes a combination of args and coerces defaults for a listener. We default
  # to a pre-hook, and async execution. I imagine this is the most common use case
  # and so it makes the most sense to default to this. It can be overriden in the
  # options (and should really always be explicit).
  def parse_listener(mod, block \\ :pre, type \\ :async) do
    def_block = case block do
      :post -> :post
      _post -> :pre
    end

    def_type = case type do
      :sync -> :sync
      _Sync -> :async
    end

    { mod, def_block, def_type }
  end

  # Starts any required listeners. We allow either a list of listeners, or a
  # single listener to ensure that users can attach N listeners (because you can
  # technically plug in modules as plugins).
  defp start_listeners(mod) when not is_list(mod), do: start_listeners([mod])
  defp start_listeners(mods) when is_list(mods) do
    mods
    |> Stream.map(fn
        (mod) when is_tuple(mod) ->
          apply(__MODULE__, :parse_listener, Tuple.to_list(mod))
        (mod) when is_list(mod) ->
          apply(__MODULE__, :parse_listener, mod)
        (mod) ->
          parse_listener(mod)
       end)
    |> Stream.map(&(start_listener/1))
    |> Stream.filter(&(&1 != nil))
    |> Enum.to_list
  end

  # Starts a listener. We check to ensure that the listener is a module before
  # trying to start it and add as a handler. If anything goes wrong at this point
  # we just nil the listener to avoid errors later.
  defp start_listener({ mod, block, type }) do
    try do
      mod.__info__(:module)
      case GenEvent.start_link do
        { :ok, pid } ->
          GenEvent.add_handler(pid, mod, [])
          { pid, block, type }
        { :error, { :already_started, pid } } ->
          { pid, block, type }
        _error -> nil
      end
    rescue
      _error -> nil
    end
  end

end
