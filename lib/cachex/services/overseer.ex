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
  import Cachex.Spec

  # add any aliases
  alias Cachex.Services

  # add service aliases
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
  Determines whether a cache is known by the Overseer.
  """
  @spec known?(atom) :: true | false
  def known?(name) when is_atom(name),
    do: :ets.member(@table_name, name)

  @doc """
  Retrieves a cache from a name or record.

  Retrieving a cache will map the provided argument to a
  cache record if available, otherwise a nil value.

  When a name resolver is configured (see `resolve_name/1`), the name is
  passed through it first, allowing the caller to be transparently routed
  to a different cache instance. This makes per-process redirection (e.g.
  test sandboxing) possible without intercepting every cache call.
  """
  @spec lookup(Cachex.t()) :: Cachex.t() | nil
  def lookup(cache() = cache),
    do: cache

  def lookup(name) when is_atom(name) do
    resolved = resolve_name(name)

    case :ets.lookup(@table_name, resolved) do
      [{^resolved, state}] ->
        state

      _other ->
        nil
    end
  end

  def lookup(_any),
    do: nil

  @doc """
  Resolves a cache name through the optionally-configured resolver.

  By default this is the identity function: the name is returned
  unchanged and there is no measurable overhead. Setting

      config :cachex, :name_resolver, &MyModule.resolve/1

  installs a `(atom -> atom)` function that is consulted on every cache
  name resolution. It must return a cache name (an atom); returning the
  same name is a no-op. This is the supported extension point for
  redirecting cache resolution per process — for example, a test-isolation
  library can return a per-test cache name based on the calling process
  (via the process dictionary or `$callers`), giving each async test its
  own isolated cache without forking or patching Cachex.

  Resolution is **not** applied recursively: the resolver's result is used
  directly as the ETS key, so a resolver must return a concrete name, not
  another name that itself needs resolving.
  """
  @spec resolve_name(atom) :: atom
  def resolve_name(name) when is_atom(name) do
    case Application.get_env(:cachex, :name_resolver) do
      nil -> name
      resolver when is_function(resolver, 1) -> resolver.(name) || name
    end
  end

  @doc """
  Registers a cache record against a name.
  """
  @spec register(atom, Cachex.t()) :: true
  def register(name, cache() = cache) when is_atom(name),
    do: :ets.insert(@table_name, {name, cache})

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
      cstate = lookup(name)
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
    state = lookup(cache)

    if state == nil do
      raise ArgumentError, "no cache available: #{inspect(cache)}"
    end

    handler.(state)
  end
end
