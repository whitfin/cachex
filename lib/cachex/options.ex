defmodule Cachex.Options do
  @moduledoc false
  # A container to ensure that all option parsing is done in a single location
  # to avoid accidentally getting mixed field names and values across the library.

  # add some aliases
  alias Cachex.Hook
  alias Cachex.Util

  defstruct cache: nil,             # the name of the cache
            ets_opts: nil,          # any options to give to ETS
            default_fallback: nil,  # the default fallback implementation
            default_ttl: nil,       # any default ttl values to use
            fallback_args: nil,     # arguments to pass to a cache loader
            pre_hooks: nil,         # any pre hooks to attach
            post_hooks: nil,        # any post hooks to attach
            nodes: nil,             # a list of nodes to connect to
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
  def parse(options \\ [])
  def parse(options) when is_list(options) do
    cache = case options[:name] do
      val when val == nil or not is_atom(val) ->
        raise ArgumentError, message: "Cache name must be a valid atom"
      val -> val
    end

    ets_opts = Keyword.get(options, :ets_opts, [
      { :read_concurrency, true },
      { :write_concurrency, true }
    ])

    default_ttl = Util.get_opt_positive(options, :default_ttl)
    ttl_interval = case Keyword.get(options, :ttl_interval) do
      val when val == true or (val == nil and default_ttl != nil) ->
        :timer.seconds(3)
      val when is_number(val) and val > 0 ->
        val
      _na ->
        nil
    end

    remote_node_list = Enum.uniq([ node | Util.get_opt_list(options, :nodes, [])])
    default_fallback = Util.get_opt_function(options, :default_fallback)

    fallback_args =
      options
      |> Util.get_opt_list(:fallback_args, [])

    hooks = case options[:hooks] do
      nil -> []
      mod -> Hook.initialize_hooks(mod)
    end

    stats_hook = case !!options[:record_stats] do
      true ->
        Hook.initialize_hooks(%Hook{
          args: [ ],
          module: Cachex.Stats,
          type: :post,
          results: true,
          server_args: [
            name: Cachex.Util.stats_for_cache(cache)
          ]
        })
      false ->
        []
    end

    pre_hooks = Hook.hooks_by_type(hooks, :pre)
    post_hooks = stats_hook ++ Hook.hooks_by_type(hooks, :post)

    is_remote = cond do
      remote_node_list != nil && remote_node_list != [node()] -> true
      !!options[:remote] -> true
      true -> false
    end

    %__MODULE__{
      "cache": cache,
      "ets_opts": ets_opts,
      "default_fallback": default_fallback,
      "default_ttl": default_ttl,
      "fallback_args": fallback_args,
      "nodes": remote_node_list,
      "pre_hooks": pre_hooks,
      "post_hooks": post_hooks,
      "remote": is_remote,
      "transactional": !!options[:transactional],
      "ttl_interval": ttl_interval
    }
  end
  def parse(_options), do: parse([])

end
