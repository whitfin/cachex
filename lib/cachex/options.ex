defmodule Cachex.Options do
  @moduledoc false
  # A container to ensure that all option parsing is done in a single location
  # to avoid accidentally getting mixed field names and values across the library.

  # access to constants
  use Cachex.Constants

  # add some aliases
  alias Cachex.Commands
  alias Cachex.Fallback
  alias Cachex.Hook
  alias Cachex.Limit
  alias Cachex.Util
  alias Cachex.Util.Names

  @doc """
  Parses a list of input options to the fields we care about, setting things like
  defaults and verifying types.

  The output of this function will be an instance of a Cachex State, that we can
  use blindly in other areas of the library. As such, this function has the
  potential to become a little messy - but that's okay, since it saves us trying
  to duplicate this logic all over the codebase.
  """
  def parse(cache, options) when is_list(options) do
    with { :ok,   ets_result } <- setup_ets(cache, options),
         { :ok,   cmd_result } <- setup_commands(cache, options),
         { :ok, limit_result } <- setup_limit(cache, options),
         { :ok,  hook_result } <- setup_hooks(cache, options, limit_result),
         { :ok, trans_result } <- setup_transactions(cache, options),
         { :ok,    fb_result } <- setup_fallbacks(cache, options),
         { :ok,   ode_result } <- setup_ode(cache, options),
         { :ok,   ttl_result } <- setup_ttl_components(cache, options)
      do
        { pre_hooks, post_hooks } = hook_result
        { transactional, locksmith } = trans_result
        { default_ttl, ttl_interval, janitor } = ttl_result

        state = %Cachex.State{
          cache: cache,
          commands: cmd_result,
          default_ttl: default_ttl,
          ets_opts: ets_result,
          fallback: fb_result,
          janitor: janitor,
          limit: limit_result,
          locksmith: locksmith,
          ode: ode_result,
          pre_hooks: pre_hooks,
          post_hooks: post_hooks,
          transactions: transactional,
          ttl_interval: ttl_interval
        }

        { :ok, state }
      end
  end
  def parse(cache, _options),
    do: parse(cache, [])

  # Parses out any custom commands to be used against invocations. We delegate
  # most of the parsing to the Commands module, here we just validate that we
  # have a Keyword List to work with, and that there are no duplicate command
  # entries (we want to keep the first to match a typical Keyword behaviour).
  def setup_commands(_cache, options) do
    options
    |> Util.get_opt(:commands, &Keyword.keyword?/1, [])
    |> Enum.uniq_by(&elem(&1, 0))
    |> Commands.parse
  end

  # Parses out a potential list of ETS options, passing through the default opts
  # used for concurrency settings. This allows them to be overridden, but it would
  # have to be explicitly overridden.
  defp setup_ets(_cache, options) do
    options
    |> Util.get_opt(:ets_opts, &is_list/1, [])
    |> Keyword.put_new(:write_concurrency, true)
    |> Keyword.put_new(:read_concurrency, true)
    |> Util.wrap(:ok)
  end

  # Sets up and fallback behaviour options. Currently this just retrieves the
  # two flags from the options list and returns them inside a tuple for storage.
  defp setup_fallbacks(_cache, options) do
    fb_opts = Util.opt_transform(options, :fallback, fn
      (fun) when is_function(fun) ->
        [ action: fun ]
      (list) when is_list(list) ->
        list
      (_inv) ->
        []
    end)

    { :ok, Fallback.parse(fb_opts) }
  end

  # Sets up any hooks to be enabled for this cache. Also parses out whether a
  # Stats hook has been requested or not. The returned value is a tuple of pre
  # and post hooks as they're stored separately.
  defp setup_hooks(cache, options, limit) do
    stats_hook = options[:record_stats] && %Hook{
      module: Cachex.Hook.Stats,
      server_args: [
        name: Names.stats(cache)
      ]
    }

    hooks_opts =
      options
      |> Keyword.get(:hooks, [])
      |> List.wrap

    hooks_list =
      limit
      |> Limit.to_hooks
      |> Enum.concat(hooks_opts)

    hooks =
      stats_hook
      |> Kernel.||([])
      |> List.wrap
      |> Enum.concat(hooks_list)

    with { :ok, hooks } <- Hook.validate(hooks) do
      groups = {
        Hook.group_by_type(hooks, :pre),
        Hook.group_by_type(hooks, :post)
      }

      { :ok, groups }
    end
  end

  # Parses out a potential cache size limit to cap the cache at. This will return
  # a Limit struct based on the provided values. If the cache has no limits, the
  # `:limit` key in the struct will be nil.
  defp setup_limit(_cache, options) do
    options
    |> Keyword.get(:limit)
    |> Limit.parse
    |> Util.wrap(:ok)
  end

  # Parses out whether the user wishes to disable on-demand expirations or not. It
  # can be disabled by setting the `:ode` flag to `false`. Defaults to `true`.
  defp setup_ode(_cache, options) do
    options
    |> Util.get_opt(:ode, &is_boolean/1, true)
    |> Util.wrap(:ok)
  end

  # Parses out whether the user wishes to utilize transactions or not. They can
  # either be enabled or disabled, represented by `true` and `false`.
  defp setup_transactions(cache, options) do
    trans_opts = {
      Util.get_opt(options, :transactions, &is_boolean/1, false),
      Names.locksmith(cache)
    }
    { :ok, trans_opts }
  end

  # Sets up and parses any options related to TTL behaviours. Currently this deals
  # with janitor naming, TTL defaults, and purge intervals.
  defp setup_ttl_components(cache, options) do
    janitor_name = Names.janitor(cache)

    default_ttl  = Util.get_opt(options, :default_ttl, fn(val) ->
      is_integer(val) and val > 0
    end)

    ttl_interval = Util.get_opt(options, :ttl_interval, &is_integer/1)

    opts = cond do
      ttl_interval == -1 ->
        { default_ttl, nil, nil }
      is_nil(ttl_interval) ->
        { default_ttl, :timer.seconds(3), janitor_name }
      true ->
        { default_ttl, ttl_interval, janitor_name }
    end

    { :ok, opts }
  end

end
