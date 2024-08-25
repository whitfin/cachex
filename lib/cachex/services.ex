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
  @spec app_spec :: [Supervisor.child_spec()]
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
  @spec cache_spec(Cachex.Spec.cache()) :: [Supervisor.Spec.spec()]
  def cache_spec(cache() = cache) do
    []
    |> Enum.concat(table_spec(cache))
    |> Enum.concat(locksmith_spec(cache))
    |> Enum.concat(informant_spec(cache))
    |> Enum.concat(incubator_spec(cache))
    |> Enum.concat(conductor_spec(cache))
    |> Enum.concat(courier_spec(cache))
    |> Enum.concat(janitor_spec(cache))
  end

  @doc """
  Links all hooks in a cache to their running process.

  This is a required post-step as hooks are started independently and
  are not named in a deterministic way. It will look up all hooks using
  the Supervisor children and place them in a modified cache record.
  """
  @spec link(Cachex.Spec.cache()) :: {:ok, Cachex.Spec.cache()}
  def link(cache(hooks: hooks(pre: [], post: []), warmers: []) = cache),
    do: {:ok, cache}

  def link(cache(hooks: hooks(pre: pre, post: post), warmers: warmers) = cache) do
    hook_children = find_children(cache, Services.Informant)
    warmer_children = find_children(cache, Services.Incubator)

    linked =
      cache(cache,
        hooks:
          hooks(
            pre: attach_child(pre, hook_children),
            post: attach_child(post, hook_children)
          ),
        warmers: attach_child(warmers, warmer_children)
      )

    {:ok, linked}
  end

  @doc """
  Retrieves the process identifier of the provided service.

  This will return `nil` if the service does not exist, or is not running.
  """
  @spec locate(Cachex.Spec.cache(), atom) :: pid | nil
  def locate(cache() = cache, service) do
    cache
    |> services
    |> find_pid(service)
  end

  @doc """
  Returns a list of all running cache services.

  This is used to view the children of the specified cache, whilst filtering
  out any services which may not have been started based on the cache options.
  """
  @spec services(Cachex.Spec.cache()) :: [Supervisor.Spec.spec()]
  def services(cache(name: cache)) do
    cache
    |> Supervisor.which_children()
    |> Enum.filter(&service?/1)
  end

  ###############
  # Private API #
  ###############

  # Creates a specification for the Conductor service.
  #
  # The Conductor service provides a way to dispatch cache calls between
  # nodes in a distributed cluster. It's a little complicated because a
  # Conductor's routing logic can be either a separate process or the
  # same process to avoid unnecessary overhead. If this makes no sense
  # when you come to read it, that's probably why.
  defp conductor_spec(cache() = cache),
    do: [
      %{
        id: Services.Conductor,
        start: {Services.Conductor, :start_link, [cache]}
      }
    ]

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
  defp table_spec(cache(name: name, compressed: compressed, ordered: ordered)) do
    server_opts = [name: name(name, :eternal), quiet: true]
    ordered_opts = (ordered && [:ordered_set]) || []
    compressed_opts = (compressed && [:compressed]) || []

    [
      %{
        id: Eternal,
        start:
          {Eternal, :start_link,
           [
             name,
             compressed_opts ++ ordered_opts ++ const(:table_options),
             server_opts
           ]},
        type: :supervisor
      }
    ]
  end

  # Iterates a list of hooks and finds their reference in list of children.
  #
  # When there is a reference found, the hook is updated with the new PID.
  defp attach_child(structs, children) do
    Enum.map(structs, fn
      warmer(module: module, name: nil) = warmer ->
        warmer(warmer, name: find_pid(children, module))

      hook(module: module, name: nil) = hook ->
        hook(hook, name: find_pid(children, module))

      value ->
        value
    end)
  end

  # Finds a list of running children for a service.
  defp find_children(cache, service) do
    case locate(cache, service) do
      nil -> []
      pid -> Supervisor.which_children(pid)
    end
  end

  # Locates a process identifier for the given module.
  #
  # This uses a list of child modules; if no child is
  # found, the value returned is nil.
  defp find_pid(children, module) do
    Enum.find_value(children, fn
      {^module, pid, _, _} -> pid
      _ -> false
    end)
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
