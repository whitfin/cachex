defmodule Cachex.Services do
  @moduledoc """
  Service specification provider for Cachex caches.

  Services can either exist for the global Cachex application or on
  a cache level. This module provides access to both in an attempt
  to group all logic into one place to make it easier to see exactly
  what exists against a cache and what doesn't.
  """
  import Cachex.Spec
  import Supervisor.Spec

  # add some aliases
  alias Cachex.Services
  alias Supervisor.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Returns a list of workers of supervisors for the global app.

  This will typically only be called once at startup, but it's separated
  out in order to make it easier to find when comparing supervisors.

  At the time of writing, the order does not matter - but that does not
  mean this will always be the case, so please be careful when modifying.
  """
  @spec app_spec :: [ Spec.spec ]
  def app_spec,
    do: [
      supervisor(Services.Overseer, []),
      supervisor(Services.Locksmith, [])
    ]

  @doc """
  Returns a list of workers or supervisors for a cache.

  This is used to set up the supervision tree on a cache by cache basis,
  rather than embedding all of this logic into the parent module.

  Definition order here matters, as there's inter-dependency between each
  of the child processes (such as the Janitor -> Locksmith).
  """
  @spec cache_spec(Spec.cache) :: [ Spec.spec ]
  def cache_spec(cache() = cache) do
    []
    |> Enum.concat(table_spec(cache))
    |> Enum.concat(locksmith_spec(cache))
    |> Enum.concat(informant_spec(cache))
    |> Enum.concat(incubator_spec(cache))
    |> Enum.concat(courier_spec(cache))
    |> Enum.concat(janitor_spec(cache))
    |> Enum.concat(limit_spec(cache))
  end

  ###############
  # Private API #
  ###############

  # Creates a specification for the Courier service.
  #
  # The courier acts as a synchronised way to retrieve values computed via
  # fallback functions to avoid clashing. Each cache should have a courier
  # by default as fallbacks are enabled by default (not behind a flag).
  defp courier_spec(cache() = cache),
    do: [ worker(Services.Courier, [ cache ]) ]

  # Creates a specification for the Incubator supervisor.
  #
  # The incubator is essentially a supervisor around all warmers in assigned
  # to a cache so they're managed correctly. If no warmers are associated to
  # the cache, this supervisor will essentially no-op at startup.
  defp incubator_spec(cache() = cache),
    do: [ supervisor(Services.Incubator, [ cache ]) ]

  # Creates a specification for the Informant supervisor.
  #
  # The Informant acts as a parent to all hooks running against a cache. It
  # should be noted that this might result in no processes if there are no
  # hooks attached to the cache at startup (meaning no supervisor either).
  defp informant_spec(cache() = cache),
    do: [ supervisor(Services.Informant, [ cache ]) ]

  # Creates a specification for the Janitor service.
  #
  # This can be an empty list if the cleanup interval is set to nil, which
  # dictates that no Janitor should be enabled for the cache.
  defp janitor_spec(cache(expiration: expiration(interval: nil))),
    do: []
  defp janitor_spec(cache() = cache),
    do: [ worker(Services.Janitor, [ cache ]) ]

  # Creates any require limit specifications for the supervision tree.
  #
  # This will rarely be used in the out-of-the-box experience, it's mainly
  # provided for use in custom limit implementations by developers.
  defp limit_spec(cache(limit: limit(size: nil))),
    do: []
  defp limit_spec(cache(limit: limit(policy: policy) = limit)) do
    case apply(policy, :child_spec, [ limit ]) do
      [] -> []
      cs ->
        strategy = apply(policy, :strategy, [])
        [ supervisor(Supervisor, [ cs, [ strategy: strategy ] ]) ]
    end
  end

  # Creates the required Locksmith queue specification for a cache.
  #
  # This will create a queue worker instance for any transactions to be
  # executed against. It should be noted that this does not start the
  # global (application-wide) Locksmith table; that should be started
  # separately on application startup using app_spec/0.
  defp locksmith_spec(cache() = cache),
    do: [ worker(Services.Locksmith.Queue, [ cache ]) ]

  # Creates the required specifications for a backing cache table.
  #
  # This specification should be included in a cache tree before any others
  # are started as we should provide the guarantee that the table exists
  # before any other services are started (to avoid race conditions).
  defp table_spec(cache(name: name)) do
    server_opts = [ name: name(name, :eternal), quiet: true ]
    [ supervisor(Eternal, [ name, const(:table_options), server_opts ]) ]
  end
end
