defmodule Cachex.Services do
  @moduledoc false
  # This module provides service specification generation for Cachex.
  #
  # Services can either exist for the global Cachex application or for
  # a specific cache. This module provides access to both in an attempt
  # to group all logic into one place to make it easier to see exactly
  # what exists against a cache and what doesn't.

  # add some aliases
  alias Cachex.LockManager
  alias Cachex.Services
  alias Cachex.State
  alias Supervisor.Spec

  # import supervisor stuff
  import Supervisor.Spec

  @doc """
  Returns a list of workers of supervisors for the global app.

  This will typically only be called once at startup, but it's separated
  out in order to make it easier to find when comparing supervisors.
  """
  @spec app_spec :: [ Spec.spec ]
  def app_spec,
    do: [
      supervisor(State, []),
      supervisor(LockManager.Table, [])
    ]

  @doc """
  Returns a list of workers or supervisors for a cache.

  This is used to set up the supervision tree on a cache by cache basis,
  rather than embedding all of this logic into the parent module.
  """
  @spec cache_spec(Cachex.cache) :: [ Spec.spec ]
  def cache_spec(cache),
    do: janitor_spec(cache)

  # Creates any required specifications for the Janitor services running
  # along a cache instance. This can be an empty list if the interval set
  # is nil (meaning that no Janitor has been enabled for the cache).
  defp janitor_spec(%State{ ttl_interval: nil }),
    do: []
  defp janitor_spec(%State{ janitor: janitor } = state),
    do: [ worker(Services.Janitor, [ state, [ name: janitor ] ]) ]
end
