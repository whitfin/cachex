defmodule Cachex.Cache do
  @moduledoc false
  # Main struct module for a Cachex cache instance.
  #
  # This represents the state being passed around when dealing with a cache. Internally
  # all calls will use an instance of this cache, even if the main API is dealing with
  # only the name of the cache (to make it convenient for callers).

  # import records
  import Cachex.Spec
  import Cachex.Errors

  # add some aliases
  alias Cachex.Spec
  alias Cachex.Util
  alias Spec.Validator

  # our opaque type
  @opaque t :: %__MODULE__{ }

  # internal state struct
  defstruct [
    name: nil,              # the name of the cache
    commands: %{},          # any custom commands attached to the cache
    default_ttl: nil,       # any default ttl values to use
    fallback: fallback(),   # the default fallback implementation
    hooks: hooks(),         # any hooks to attach to the cache
    limit: limit(),         # any limit to apply to the cache
    ode: true,              # whether we enable on-demand expiration
    transactions: false,    # whether to enable transactions
    ttl_interval: nil       # the ttl check interval
  ]

  @doc """
  Parses a list of cache options into a `Cachex.Cache` instance.

  This will validate any options and error on anything we don't understand. The
  advantage of binding into a cache instance is that we can blindly use it in
  other areas of the library without needing to validate. As such, this code can
  easily become a little messy - but that's ok!
  """
  @spec create(atom, Keyword.t) :: { :ok, __MODULE__.t } | { :error, atom }
  def create(name, options) when is_list(options) do
    # complex parsing statements which can fail out early
    with { :ok,   cmd_result } <- setup_commands(name, options),
         { :ok, limit_result } <- setup_limit(name, options),
         { :ok,  hook_result } <- setup_hooks(name, options, limit_result),
         { :ok,    fb_result } <- setup_fallbacks(name, options),
         { :ok,   ttl_result } <- setup_ttl_components(name, options),

         # basic parsing which doesn't have the opportunity to fail
         ode_enabled   = Util.get_opt(options, :ode, &is_boolean/1, true),
         transactional = Util.get_opt(options, :transactions, &is_boolean/1, false)
      do
        { default_ttl, ttl_interval } = ttl_result

        { :ok, %__MODULE__{
          name: name,
          commands: cmd_result,
          default_ttl: default_ttl,
          fallback: fb_result,
          hooks: hook_result,
          limit: limit_result,
          ode: ode_enabled,
          transactions: transactional,
          ttl_interval: ttl_interval
        } }
      end
  end

  # Parses out any custom commands to be used for custom invocations.
  #
  # We delegate most of the parsing to the Commands module; here we just check
  # that we have a Keyword List to work with, and that there are not duplicate
  # command entries (we want to keep the first to match a typical Keyword behaviour).
  def setup_commands(_name, options) do
    commands =
      Util.opt_transform(options, :commands, fn
        # map parsing is allowed
        (map) when is_map(map) -> map

        # keyword list parsing is allowed
        (list) when is_list(list) -> list

        # missing is fine
        (nil) -> []

        # anything else, nope!
        (_invalid) -> nil
      end)

    case commands do
      nil  -> error(:invalid_command)
      cmds ->
        validated =
        Enum.all?(cmds, fn
          ({ _name, command }) ->
            Validator.valid?(:command, command)
          (_invalid_elements) ->
            false
        end)

      case validated do
        false -> error(:invalid_command)
        true  ->
          cmds
          |> Enum.reverse
          |> Enum.into(%{})
          |> wrap(:ok)
      end
    end
  end

  # Sets up any cache-wide fallback behaviour.
  #
  # This will allow the shorthanding of a function to act as a default
  # fallback implementation; otherwise the provided value must be a
  # fallback record which is run through the specification validation.
  defp setup_fallbacks(_name, options) do
    fallback =
      Util.opt_transform(options, :fallback, fn
        # provided fallback is great!
        (fallback() = fallback) ->
          fallback

        # allow shorthand of a function
        (fun) when is_function(fun) ->
          fallback(default: fun)

        # unset so default
        (nil) ->
          fallback()

        # anything else, no thanks!
        (_invalid) ->
          nil
      end)

    # validate using the spec validator
    case Validator.valid?(:fallback, fallback) do
      false -> error(:invalid_fallback)
      true  -> { :ok, fallback }
    end
  end

  # Configures any hooks to be enabled for the cache.
  #
  # In addition to the hooks already provided, this will also deal with the
  # notion of statistics hooks and limits, as they can both define hooks.
  defp setup_hooks(name, options, limit) do
    hooks = Enum.concat([
      # stats hook generation
      case !!options[:stats] do
        false -> []
        true  -> [ hook(
          module: Cachex.Hook.Stats,
          options: [ name: name(name, :stats) ]
        ) ]
      end,

      # limit hook generation
      case limit do
        limit(size: nil) ->
          []
        limit(policy: policy) ->
          apply(policy, :hooks, [ limit ])
      end,

      # provided hooks lists
      options
      |> Keyword.get(:hooks, [])
      |> List.wrap
    ])

    # validation of all hooks and division into a hooks record
    case Enum.all?(hooks, &Validator.valid?(:hook, &1)) do
      false ->
        error(:invalid_hook)
      true  ->
        type = Enum.group_by(hooks, &hook(&1, :type))

        pre  = Map.get(type,  :pre, [])
        post = Map.get(type, :post, [])

        { :ok, hooks(pre: pre, post: post) }
    end
  end

  # Sets up any provided limit structures.
  #
  # This will allow shorthanding of a numeric value to act as a size
  # to bound the cache to. This will provide defaults for all other
  # fields in the limit structure.
  defp setup_limit(_name, options) do
    limit =
      case Keyword.get(options, :limit) do
        limit() = limit -> limit
        size -> limit(size: size)
      end

    case Validator.valid?(:limit, limit) do
      false -> error(:invalid_limit)
      true  -> { :ok, limit }
    end
  end

  # Sets up and parses any options related to TTL behaviours.
  #
  # Currently this deals with janitor naming, TTL defaults, and purge intervals.
  defp setup_ttl_components(_name, options) do
    default_ttl  = Util.get_opt(options, :default_ttl, &is_positive_integer/1)
    case Util.get_opt(options, :ttl_interval, &is_integer/1) do
       -1 -> { :ok, { default_ttl, nil } }
      nil -> { :ok, { default_ttl, :timer.seconds(3) } }
      val -> { :ok, { default_ttl, val } }
    end
  end
end
