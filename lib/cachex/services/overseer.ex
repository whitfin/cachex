defmodule Cachex.Services.Overseer do
  @moduledoc false
  # Service module overseeing the persistence of cache records.
  #
  # This module controls the state of caches being handled by Cachex. This was
  # originally part of an experiment to see if it was viable to remove a process
  # which backed each cache to avoid bottlenecking scenarios and grant the develop
  # finer control over their concurrency.
  #
  # The result was much higher throughput with better flexibility, and so we kept
  # this new design. Cache states are stored in a single ETS table backing this
  # module and all cache calls will be routed through here first to ensure their
  # state is up to date.
  import Cachex.Error
  import Cachex.Spec

  # add any aliases
  alias Cachex.Services

  # add service aliases
  alias Services.Overseer
  alias Services.Steward

  # constants for manager/table names
  @table_name :cachex_overseer_table
  @manager_name :cachex_overseer_manager

  ##############
  # Public API #
  ##############

  @doc """
  Creates a new Overseer service tree.

  This will start a basic `Agent` for transactional changes, as well
  as the main ETS table backing this service.
  """
  @spec start_link :: Supervisor.on_start()
  def start_link do
    ets_opts = [read_concurrency: true, write_concurrency: true]
    tab_opts = [@table_name, ets_opts, [quiet: true]]
    mgr_opts = [1, [name: @manager_name]]

    children = [
      %{id: :sleeplocks, start: {:sleeplocks, :start_link, mgr_opts}},
      %{id: Eternal, start: {Eternal, :start_link, tab_opts}, type: :supervisor}
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: :cachex_overseer
    )
  end

  @doc """
  Retrieves a cache from a name or record.

  Retrieving a cache will map the provided argument to a
  cache record if available, otherwise a nil value.
  """
  @spec get(Cachex.t()) :: Cachex.t() | nil
  def get(cache() = cache),
    do: cache

  def get(name) when is_atom(name),
    do: retrieve(name)

  def get(_miss),
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
  @spec register(atom, Cachex.t()) :: true
  def register(name, cache() = cache) when is_atom(name),
    do: :ets.insert(@table_name, {name, cache})

  @doc """
  Retrieves a cache record, or `nil` if none exists.
  """
  @spec retrieve(atom) :: Cachex.t() | nil
  def retrieve(name) do
    case :ets.lookup(@table_name, name) do
      [{^name, state}] ->
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
    do: Enum.member?(:ets.all(), @table_name)

  @doc """
  Carries out a transaction against the state table.
  """
  @spec transaction(atom, (-> any)) :: any
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
  @spec update(atom, Cachex.t() | (Cachex.t() -> Cachex.t())) :: Cachex.t()
  def update(name, fun) when is_atom(name) and is_function(fun, 1) do
    transaction(name, fn ->
      cstate = retrieve(name)
      nstate = fun.(cstate)

      register(name, nstate)

      Steward.provide(nstate, {:cache, nstate})

      nstate
    end)
  end

  def update(name, cache(name: name) = cache),
    do: update(name, fn _ -> cache end)

  @doc """
  Executes a cache handler with a cache record.
  """
  @spec with(cache :: Cachex.t(), (cache :: Cachex.t() -> any)) :: any
  def with(cache, handler) do
    case Overseer.get(cache) do
      nil ->
        error(:no_cache)

      cache(name: name) = cache ->
        if :erlang.whereis(name) != :undefined do
          handler.(cache)
        else
          error(:no_cache)
        end
    end
  end
end
