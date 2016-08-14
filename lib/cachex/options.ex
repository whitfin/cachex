defmodule Cachex.Options do
  @moduledoc false
  # A container to ensure that all option parsing is done in a single location
  # to avoid accidentally getting mixed field names and values across the library.

  # add some aliases
  alias Cachex.Hook
  alias Cachex.Util

  defstruct cache: nil,             # the name of the cache
            disable_ode: false,     # whether we disable on-demand expiration
            ets_opts: nil,          # any options to give to ETS
            default_fallback: nil,  # the default fallback implementation
            default_ttl: nil,       # any default ttl values to use
            fallback_args: nil,     # arguments to pass to a cache loader
            janitor: nil,           # the name of the janitor attached (if any)
            pre_hooks: nil,         # any pre hooks to attach
            post_hooks: nil,        # any post hooks to attach
            ttl_interval: nil       # the ttl check interval

  @doc """
  Parses a list of input options to the fields we care about, setting things like
  defaults and verifying types. The output of this function should be a set of
  options that we can use blindly in other areas of the library. As such, this
  function has the potential to become a little messy - but that's okay, since
  it saves us trying to duplicate this logic all over the codebase.
  """
  def parse(options \\ [])
  def parse(options) when is_list(options) do
    cache = case options[:name] do
      val when val == nil or not is_atom(val) ->
        raise ArgumentError, message: "Cache name must be a valid atom"
      val -> val
    end

    onde_dis = Util.truthy?(options[:disable_ode])
    ets_opts = Keyword.get(options, :ets_opts, [
      { :read_concurrency, true },
      { :write_concurrency, true }
    ])

    { pre_hooks, post_hooks } = setup_hooks(cache, options)
    { default_fallback, fallback_args } = setup_fallbacks(cache, options)
    { default_ttl, ttl_interval, janitor } = setup_ttl_components(cache, options)

    %__MODULE__{
      "cache": cache,
      "disable_ode": onde_dis,
      "ets_opts": ets_opts,
      "default_fallback": default_fallback,
      "default_ttl": default_ttl,
      "fallback_args": fallback_args,
      "janitor": janitor,
      "pre_hooks": pre_hooks,
      "post_hooks": post_hooks,
      "ttl_interval": ttl_interval
    }
  end
  def parse(_options), do: parse([])

  # Sets up and fallback behaviour options. Currently this just retrieves the
  # two flags from the options list and returns them inside a tuple for storage.
  defp setup_fallbacks(_cache, options), do: {
    Util.get_opt_function(options, :default_fallback),
    Util.get_opt_list(options, :fallback_args, [])
  }

  # Sets up any hooks to be enabled for this cache. Also parses out whether a
  # Stats hook has been requested or not. The returned value is a tuple of pre
  # and post hooks as they're stored separately.
  defp setup_hooks(cache, options) do
    stats_hook = options[:record_stats] && %Hook{
      args: [ ],
      module: Cachex.Stats,
      type: :post,
      results: true,
      server_args: [
        name: Util.stats_for_cache(cache)
      ]
    }

    hooks =
      [stats_hook]
      |> Enum.concat(List.wrap(options[:hooks] || []))
      |> Hook.initialize_hooks

    {
      Hook.hooks_by_type(hooks, :pre),
      Hook.hooks_by_type(hooks, :post)
    }
  end

  # Sets up and parses any options related to TTL behaviours. Currently this deals
  # with janitor naming, TTL defaults, and purge intervals.
  defp setup_ttl_components(cache, options) do
    janitor_name = Util.janitor_for_cache(cache)
    default_ttl  = Util.get_opt_positive(options, :default_ttl)

    case Keyword.get(options, :ttl_interval) do
      val when val == true or (val == nil and default_ttl != nil) ->
        { default_ttl, :timer.seconds(3), janitor_name }
      val when is_number(val) and val > 0 ->
        { default_ttl, val, janitor_name }
      _na ->
        { default_ttl, nil, nil }
    end
  end

end
