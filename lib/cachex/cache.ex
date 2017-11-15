defmodule Cachex.Cache do
  @moduledoc false
  # Main struct module for a Cachex cache instance.
  #
  # This represents the state being passed around when dealing with a cache. Internally
  # all calls will use an instance of this cache, even if the main API is dealing with
  # only the name of the cache (to make it convenient for callers).

  # add any aliases
  alias Cachex.Fallback
  alias Cachex.Limit

  # our opaque type
  @opaque t :: %__MODULE__{ }

  # internal state struct
  defstruct name: nil,              # the name of the cache
            commands: %{},          # any custom commands attached to the cache
            ets_opts: [],           # any options to give to ETS
            default_ttl: nil,       # any default ttl values to use
            fallback: %Fallback{},  # the default fallback implementation
            janitor: nil,           # the name of the janitor attached (if any)
            limit: %Limit{},        # any limit to apply to the cache
            locksmith: nil,         # the name of the locksmith queue attached
            ode: true,              # whether we enable on-demand expiration
            pre_hooks: [],          # any pre hooks to attach
            post_hooks: [],         # any post hooks to attach
            transactions: false,    # whether to enable transactions
            ttl_interval: nil       # the ttl check interval
end
