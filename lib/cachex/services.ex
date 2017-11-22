defmodule Cachex.Services do
  @moduledoc false
  # This module provides service specification generation for Cachex.
  #
  # Services can either exist for the global Cachex application or for
  # a specific cache. This module provides access to both in an attempt
  # to group all logic into one place to make it easier to see exactly
  # what exists against a cache and what doesn't.

  # we need constants
  import Cachex.Spec

  # add some aliases
  alias Cachex.Cache
  alias Cachex.Services
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
  @spec cache_spec(Cache.t) :: [ Spec.spec ]
  def cache_spec(%Cache{ } = cache) do
    []
    |> Enum.concat(table_spec(cache))
    |> Enum.concat(locksmith_spec(cache))
    |> Enum.concat(informant_spec(cache))
    |> Enum.concat(janitor_spec(cache))
  end

  # Creates the required specification for the informant supervisor, which
  # acts as a parent to all hooks running against a cache. It should be
  # noted that this might result in no processes if no hooks are connected
  # to the cache at startup (meaning the supervisor will terminate).
  defp informant_spec(%Cache{ } = cache),
    do: [ supervisor(Services.Informant, [ cache ]) ]

  # Creates any required specifications for the Janitor services running
  # along a cache instance. This can be an empty list if the interval set
  # is nil (meaning that no Janitor has been enabled for the cache).
  defp janitor_spec(%Cache{ ttl_interval: nil }),
    do: []
  defp janitor_spec(%Cache{ } = cache),
    do: [ worker(Services.Janitor, [ cache ]) ]

  # Creates any required specifications for the Locksmith services running
  # alongside a cache instance. This will create a queue instance for any
  # transactions executed; it does not start the global Locksmith table.
  defp locksmith_spec(%Cache{ } = cache),
    do: [ worker(Services.Locksmith.Queue, [ cache ]) ]

  # Creates the required specifications for the backing cache table. This
  # spec should be included before any others in the main parent spec.
  defp table_spec(%Cache{ name: name }) do
    server_opts = [ name: name(name, :eternal), quiet: true ]
    [ supervisor(Eternal, [ name, const(:table_options), server_opts ]) ]
  end
end
