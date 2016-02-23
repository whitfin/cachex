defmodule Cachex.Options do
  @moduledoc false
  # A container to ensure that all option parsing is done in a single location
  # to avoid accidentally getting mixed field names and values across the library.

  defstruct cache: nil,             # the name of the cache
            ets_opts: nil,          # any options to give to ETS
            default_fallback: nil,  # the default fallback implementation
            default_ttl: nil,       # any default ttl values to use
            fallback_args: nil,     # arguments to pass to a cache loader
            ttl_interval: nil,      # the ttl check interval
            record_stats: nil       # if we should store stats

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
      args -> Enum.reduce(args, {}, &(Tuple.append(&2, &1)))
    end

    %__MODULE__{
      "cache": cache,
      "ets_opts": ets_opts,
      "default_fallback": default_fallback,
      "default_ttl": default_ttl,
      "fallback_args": fallback_args,
      "ttl_interval": ttl_interval,
      "record_stats": !!options[:record_stats]
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

end
