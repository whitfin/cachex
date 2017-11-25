defmodule Cachex.Options do
  @moduledoc false
  # A container to ensure that all option parsing is done in a single location
  # to avoid accidentally getting mixed field names and values across the library.

  # access to constants
  import Cachex.Spec
  import Cachex.Errors

  # add some aliases
  alias Cachex.Commands
  alias Cachex.Hook
  alias Cachex.Spec
  alias Cachex.Util

  @doc """
  Parses a list of input options to the fields we care about, setting things like
  defaults and verifying types.

  The output of this function will be an instance of a Cachex Cache, that we can
  use blindly in other areas of the library. As such, this function has the
  potential to become a little messy - but that's okay, since it saves us trying
  to duplicate this logic all over the codebase.
  """
  def parse(name, options) when is_list(options) do
    with { :ok,   cmd_result } <- setup_commands(name, options),
         { :ok, limit_result } <- setup_limit(name, options),
         { :ok,  hook_result } <- setup_hooks(name, options, limit_result),
         { :ok, trans_result } <- setup_transactions(name, options),
         { :ok,    fb_result } <- setup_fallbacks(name, options),
         { :ok,   ode_result } <- setup_ode(name, options),
         { :ok,   ttl_result } <- setup_ttl_components(name, options)
      do
        { default_ttl, ttl_interval } = ttl_result

        { :ok, %Cachex.Cache{
          name: name,
          commands: cmd_result,
          default_ttl: default_ttl,
          fallback: fb_result,
          hooks: hook_result,
          limit: limit_result,
          ode: ode_result,
          transactions: trans_result,
          ttl_interval: ttl_interval
        } }
      end
  end
  def parse(name, _options),
    do: parse(name, [])

  # Parses out any custom commands to be used against invocations. We delegate
  # most of the parsing to the Commands module, here we just validate that we
  # have a Keyword List to work with, and that there are no duplicate command
  # entries (we want to keep the first to match a typical Keyword behaviour).
  def setup_commands(_name, options) do
    options
    |> Util.get_opt(:commands, &Keyword.keyword?/1, [])
    |> Enum.uniq_by(&elem(&1, 0))
    |> Commands.parse
  end

  # Sets up and fallback behaviour options. Currently this just retrieves the
  # two flags from the options list and returns them inside a tuple for storage.
  defp setup_fallbacks(_name, options) do
    parsed_fallback =
      Util.opt_transform(options, :fallback, fn
        (fun) when is_function(fun) ->
          fallback(default: fun)

        (opts) when is_list(opts) ->
          fallback([
            provide: Keyword.get(opts, :provide),
            default: Util.get_opt(opts, :default, &is_function/1)
          ])

        (_inv) ->
          fallback()
      end)

    { :ok, parsed_fallback }
  end

  # Sets up any hooks to be enabled for this cache. Also parses out whether a
  # Stats hook has been requested or not. The returned value is a tuple of pre
  # and post hooks as they're stored separately.
  defp setup_hooks(name, options, limit) do
    stats_hook =
      options[:stats] == true && [ %Hook{
        module: Cachex.Hook.Stats,
        server_args: [ name: name(name, :stats) ]
      } ]

    hooks_opts =
      options
      |> Keyword.get(:hooks, [])
      |> List.wrap

    limit_hooks =
      case limit do
        limit(size: nil) ->
          []
        limit(policy: policy) ->
          apply(policy, :hooks, [ limit ])
      end

    hooks = Enum.concat([
      stats_hook || [],
      limit_hooks,
      hooks_opts
    ])

    with { :ok, hooks } <- Hook.validate(hooks) do
      type = Enum.group_by(hooks, &Map.get(&1, :type))

      pre  = Map.get(type,  :pre, [])
      post = Map.get(type, :post, [])

      { :ok, hooks(pre: pre, post: post) }
    end
  end

  # Parses out a potential cache size limit to cap the cache at. This will return
  # a Limit struct based on the provided values. If the cache has no limits, the
  # `:limit` key in the struct will be nil.
  defp setup_limit(_name, options) do
    limit =
      case Keyword.get(options, :limit) do
        limit() = limit -> limit
        size -> limit(size: size)
      end

    case Spec.valid?(limit) do
      true  -> { :ok, limit }
      false -> error(:invalid_limit)
    end
  end

  # Parses out whether the user wishes to disable on-demand expirations or not. It
  # can be disabled by setting the `:ode` flag to `false`. Defaults to `true`.
  defp setup_ode(_name, options) do
    options
    |> Util.get_opt(:ode, &is_boolean/1, true)
    |> Util.wrap(:ok)
  end

  # Parses out whether the user wishes to utilize transactions or not. They can
  # either be enabled or disabled, represented by `true` and `false`.
  defp setup_transactions(_name, options) do
    options
    |> Util.get_opt(:transactions, &is_boolean/1, false)
    |> Util.wrap(:ok)
  end

  # Sets up and parses any options related to TTL behaviours. Currently this deals
  # with janitor naming, TTL defaults, and purge intervals.
  defp setup_ttl_components(_name, options) do
    default_ttl  = Util.get_opt(options, :default_ttl, fn(val) ->
      is_integer(val) and val > 0
    end)

    ttl_interval = Util.get_opt(options, :ttl_interval, &is_integer/1)

    opts = cond do
      ttl_interval == -1 ->
        { default_ttl, nil }
      is_nil(ttl_interval) ->
        { default_ttl, :timer.seconds(3) }
      true ->
        { default_ttl, ttl_interval }
    end

    { :ok, opts }
  end
end
