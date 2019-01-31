defmodule Cachex.Services.Overseer do
  @moduledoc """
  Service module overseeing the persistence of cache records.

  This module controls the state of caches being handled by Cachex. This was
  originally part of an experiment to see if it was viable to remove a process
  which backed each cache to avoid bottlenecking scenarios and grant the develop
  finer control over their concurrency.

  The result was much higher throughput with better flexibility, and so we kept
  this new design. Cache states are stored in a single ETS table backing this
  module and all cache calls will be routed through here first to ensure their
  state is up to date.
  """
  import Cachex.Errors
  import Cachex.Spec

  # add any aliases
  alias Cachex.Services
  alias Supervisor.Spec

  # add service aliases
  alias Services.Overseer

  # constants for manager/table names
  @manager_name :cachex_overseer_manager
  @table_name   :cachex_overseer_table

  ##############
  # Public API #
  ##############

  @doc """
  Creates a new Overseer service tree.

  This will start a basic `Agent` for transactional changes, as well
  as the main ETS table backing this service.
  """
  @spec start_link :: Supervisor.on_start
  def start_link do
    ets_opts = [ read_concurrency: true, write_concurrency: true ]
    tab_opts = [ @table_name, ets_opts, [ quiet: true ] ]
    mgr_opts = [ 1, [ name: @manager_name ] ]

    children = [
      Spec.worker(:sleeplocks, mgr_opts),
      Spec.supervisor(Eternal, tab_opts)
    ]

    Supervisor.start_link(children, [
      strategy: :one_for_one,
      name: :cachex_overseer
    ])
  end

  @doc """
  Ensures a cache from a name or record.

  Ensuring a cache will map the provided argument to a
  cache record if available, otherwise a nil value.
  """
  @spec ensure(atom | Spec.cache) :: Spec.cache | nil
  def ensure(cache() = cache),
    do: cache
  def ensure(name) when is_atom(name),
    do: retrieve(name)
  def ensure(_miss),
    do: nil

  @doc """
  Determines whether a cache is known by the Overseer.
  """
  @spec known?(atom) :: true | false
  def known?(name) when is_atom(name),
    do: :ets.member(@table_name, name)

  @doc """
  Registers a cache record against a name.
  """
  @spec register(atom, Spec.cache) :: true
  def register(name, cache() = cache) when is_atom(name),
    do: :ets.insert(@table_name, { name, cache })

  @doc """
  Retrieves a cache record, or `nil` if none exists.
  """
  @spec retrieve(atom) :: Spec.cache | nil
  def retrieve(name) do
    case :ets.lookup(@table_name, name) do
      [{ ^name, state }] ->
        state
      _other ->
        nil
    end
  end

  @doc """
  Determines whether the Overseer has been started.
  """
  @spec started? :: boolean
  def started?,
    do: Enum.member?(:ets.all, @table_name)

  @doc """
  Carries out a transaction against the state table.
  """
  @spec transaction(atom, (() -> any)) :: any
  def transaction(name, fun) when is_atom(name) and is_function(fun, 0),
    do: :sleeplocks.execute(@manager_name, fun)

  @doc """
  Unregisters a cache record against a name.
  """
  @spec unregister(atom) :: true
  def unregister(name) when is_atom(name),
    do: :ets.delete(@table_name, name)

  @doc """
  Updates a cache record against a name.

  This is atomic and happens inside a transaction to ensure that we don't get
  out of sync. Hooks are notified of the change, and the new state is returned.
  """
  @spec update(atom, Spec.cache | (Spec.cache -> Spec.cache)) :: Spec.cache
  def update(name, fun) when is_atom(name) and is_function(fun, 1) do
    transaction(name, fn ->
      cstate = retrieve(name)
      nstate = fun.(cstate)

      register(name, nstate)

      with hooks(pre: pre_hooks, post: post_hooks) <- cache(nstate, :hooks) do
        pre_hooks
        |> Enum.concat(post_hooks)
        |> Enum.filter(&requires_state?/1)
        |> Enum.map(&hook(&1, :name))
        |> Enum.each(&send(&1, { :cachex_provision, { :cache, nstate } }))
      end

      nstate
    end)
  end
  def update(name, cache(name: name) = cache),
    do: update(name, fn _ -> cache end)

  ##########
  # Macros #
  ##########

  @doc false
  # Enforces a cache binding into a cache record.
  #
  # This will coerce cache names into a cache record, whilst just
  # returning the provided instance if it's already a cache. If
  # the cache cannot be coerced into an instance, a nil value
  # is returned.
  #
  # TODO: this can be optimized further (i.e. at all)
  defmacro enforce(cache, do: body) do
    quote do
      case Overseer.ensure(unquote(cache)) do
        nil ->
          error(:no_cache)
        var!(cache) ->
          cache = var!(cache)
          if :erlang.whereis(cache(cache, :name)) != :undefined do
            unquote(body)
          else
            error(:no_cache)
          end
      end
    end
  end

  ###############
  # Private API #
  ###############

  # Verifies if a hook has a cache provisioned.
  defp requires_state?(hook(module: module)),
    do: :cache in module.provisions()
end
