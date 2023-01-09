defmodule Cachex.Services do
  @moduledoc """
  Service specification provider for Cachex caches.

  Services can either exist for the global Cachex application or on
  a cache level. This module provides access to both in an attempt
  to group all logic into one place to make it easier to see exactly
  what exists against a cache and what doesn't.
  """
  import Cachex.Spec

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
  @spec app_spec :: [Spec.spec()]
  def app_spec,
    do: [
      %{
        id: Services.Overseer,
        start: {Services.Overseer, :start_link, []},
        type: :supervisor
      },
      %{
        id: Services.Locksmith,
        start: {Services.Locksmith, :start_link, []},
        type: :supervisor
      }
    ]

  @doc """
  Returns a list of workers or supervisors for a cache.

  This is used to set up the supervision tree on a cache by cache basis,
  rather than embedding all of this logic into the parent module.

  Definition order here matters, as there's inter-dependency between each
  of the child processes (such as the Janitor -> Locksmith).
  """
  @spec cache_spec(Spec.cache()) :: [Spec.spec()]
  def cache_spec(cache() = cache) do
    []
    |> Enum.concat(table_spec(cache))
    |> Enum.concat(locksmith_spec(cache))
    |> Enum.concat(informant_spec(cache))
    |> Enum.concat(incubator_spec(cache))
    |> Enum.concat(courier_spec(cache))
    |> Enum.concat(janitor_spec(cache))
  end

  @doc """
  Retrieves the process identifier of the provided service.

  This will return `nil` if the service does not exist, or is not running.
  """
  @spec locate(Spec.cache(), atom) :: pid | nil
  def locate(cache() = cache, service) do
    Enum.find_value(services(cache), fn
      {^service, pid, _tag, _id} -> pid
      _ -> false
    end)
  end

  @doc """
  Returns a list of all running cache services.

  This is used to view the children of the specified cache, whilst filtering
  out any services which may not have been started based on the cache options.
  """
  @spec services(Spec.cache()) :: [Spec.spec()]
  def services(cache(name: cache)) do
    cache
    |> Supervisor.which_children()
    |> Enum.filter(&service?/1)
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
    do: [
      %{
        id: Services.Courier,
        start: {Services.Courier, :start_link, [cache]}
      }
    ]

  # Creates a specification for the Incubator supervisor.
  #
  # The incubator is essentially a supervisor around all warmers in assigned
  # to a cache so they're managed correctly. If no warmers are associated to
  # the cache, this supervisor will essentially no-op at startup.
  defp incubator_spec(cache() = cache),
    do: [
      %{
        id: Services.Incubator,
        start: {Services.Incubator, :start_link, [cache]},
        type: :supervisor
      }
    ]

  # Creates a specification for the Informant supervisor.
  #
  # The Informant acts as a parent to all hooks running against a cache. It
  # should be noted that this might result in no processes if there are no
  # hooks attached to the cache at startup (meaning no supervisor either).
  defp informant_spec(cache() = cache),
    do: [
      %{
        id: Services.Informant,
        start: {Services.Informant, :start_link, [cache]},
        type: :supervisor
      }
    ]

  # Creates a specification for the Janitor service.
  #
  # This can be an empty list if the cleanup interval is set to nil, which
  # dictates that no Janitor should be enabled for the cache.
  defp janitor_spec(cache(expiration: expiration(interval: nil))),
    do: []

  defp janitor_spec(cache() = cache),
    do: [
      %{
        id: Services.Janitor,
        start: {Services.Janitor, :start_link, [cache]}
      }
    ]

  # Creates the required Locksmith queue specification for a cache.
  #
  # This will create a queue worker instance for any transactions to be
  # executed against. It should be noted that this does not start the
  # global (application-wide) Locksmith table; that should be started
  # separately on application startup using app_spec/0.
  defp locksmith_spec(cache() = cache),
    do: [
      %{
        id: Services.Locksmith.Queue,
        start: {Services.Locksmith.Queue, :start_link, [cache]}
      }
    ]

  # Creates the required specifications for a backing cache table.
  #
  # This specification should be included in a cache tree before any others
  # are started as we should provide the guarantee that the table exists
  # before any other services are started (to avoid race conditions).
  defp table_spec(cache(name: name, compressed: compressed)) do
    server_opts = [name: name(name, :eternal), quiet: true]
    tables_opts = (compressed && [:compressed]) || []

    [
      %{
        id: Eternal,
        start:
          {Eternal, :start_link,
           [
             name,
             tables_opts ++ const(:table_options),
             server_opts
           ]},
        type: :supervisor
      }
    ]
  end

  # Determines if a module is a Cachex service.
  #
  # This is done by just checking if the module starts with the namespace
  # of the Cachex services (also known as `Cachex.Services.`).
  defp service?({_service, :undefined, _tag, _id}),
    do: false

  defp service?({service, _pid, _tag, _id}) do
    service
    |> Atom.to_string()
    |> String.starts_with?("Elixir.Cachex.Services.")
  end
end
