defmodule Cachex.Services.Overseer do
  @moduledoc false
  # This module controls the state of caches being handled by Cachex. This is part
  # of an experiment to see if it's viable to remove the internal GenServer to
  # avoid several bottleneck scenarios, at well as letting the developer choose
  # how to control their concurrency.
  #
  # States are stored inside an ETS table which is started via `Cachex.Application`
  # and should only be accessed via this module. The interface is deliberately
  # small in order to reduce potential complexity.

  # require our includes
  import Cachex.Errors
  import Cachex.Spec

  # add any aliases
  alias Cachex.Cache
  alias Cachex.Hook
  alias Cachex.Services
  alias Supervisor.Spec

  # add service aliases
  alias Services.Overseer

  # constants for manager/table names
  @manager_name :cachex_overseer_manager
  @table_name   :cachex_overseer_table

  @doc """
  Starts the main supervision tree for an Overseer process.

  This will start the child table for state tracking and an Agent process which
  is used as a simple queue to allow for transactional modifications.
  """
  def start_link do
    ets_opts = [ read_concurrency: true, write_concurrency: true ]
    tab_opts = [ @table_name, ets_opts, [ quiet: true ] ]
    svr_opts = [ fn -> :ok end, [ name: @manager_name ] ]

    children = [
      Spec.worker(Agent, svr_opts),
      Spec.supervisor(Eternal, tab_opts)
    ]

    Supervisor.start_link(children, [
      strategy: :one_for_one,
      name: :cachex_overseer
    ])
  end

  @doc """
  Enforces a cache binding into a `Cachex.Cache` instance.

  This will coerce cache names into a `Cachex.Cache` insatnce, whilst just
  returning the provided instance if it's already a cache. If the cache
  cannot be coerced into an instance, a nil value is returned.
  """
  defmacro enforce(cache, do: body) do
    quote location: :keep do
      case Overseer.ensure(unquote(cache)) do
        nil ->
          error(:no_cache)
        var!(cache) ->
          cache = var!(cache)
          if :erlang.whereis(cache.name) != :undefined do
            unquote(body)
          else
            error(:no_cache)
          end
      end
    end
  end

  @doc """
  Removes a state from the local state table.
  """
  @spec del(atom) :: true
  def del(name) when is_atom(name),
    do: :ets.delete(@table_name, name)

  @doc """
  Ensures a state from a cache name or state.
  """
  @spec ensure(atom | Cache.t) :: Cache.t | nil
  def ensure(%Cache{ } = cache),
    do: cache
  def ensure(name) when is_atom(name),
    do: get(name)
  def ensure(_miss),
    do: nil

  @doc """
  Retrieves a state from the local state table, or `nil` if none exists.
  """
  @spec get(atom) :: Cache.t | nil
  def get(name) do
    case :ets.lookup(@table_name, name) do
      [{ ^name, state }] ->
        state
      _other ->
        nil
    end
  end

  @doc """
  Determines whether the given cache is provided in the state table.
  """
  @spec member?(atom) :: true | false
  def member?(name) when is_atom(name),
    do: :ets.member(@table_name, name)

  @doc """
  Sets a state in the local state table.
  """
  @spec set(atom, Cache.t) :: true
  def set(name, %Cache{ } = cache) when is_atom(name),
    do: :ets.insert(@table_name, { name, cache })

  @doc """
  Determines whether the tables for this module have been setup correctly.
  """
  @spec setup? :: true | false
  def setup?,
    do: Enum.member?(:ets.all, @table_name)

  @doc """
  Returns the name of the local state table.
  """
  @spec table_name :: atom
  def table_name,
    do: @table_name

  @doc """
  Carries out a blocking set of actions against the state table.
  """
  @spec transaction(atom, ( -> any)) :: any
  def transaction(name, fun) when is_atom(name) and is_function(fun, 0) do
    Agent.get(@manager_name, fn(cache) ->
      try do
        fun.()
      rescue
        _ -> cache
      end
    end)
  end

  @doc """
  Updates a state inside the local state table.

  This is atomic and happens inside a transaction to ensure that we don't get
  out of sync. Hooks are notified of the change, and the new state is returned.
  """
  @spec update(atom, Cache.t | (Cache.t -> Cache.t)) :: Cache.t
  def update(name, fun) when is_atom(name) and is_function(fun, 1) do
    transaction(name, fn ->
      cstate = get(name)
      nstate = fun.(cstate)

      set(name, nstate)

      with hooks(pre: pre_hooks, post: post_hooks) <- nstate.hooks do
        pre_hooks
        |> Enum.concat(post_hooks)
        |> Enum.filter(&requires_state?/1)
        |> Enum.each(&send(&1.ref, { :provision, { :cache, nstate } }))
      end

      nstate
    end)
  end
  def update(name, %Cache{ } = cache) when is_atom(name),
    do: update(name, fn _ -> cache end)

  # Verifies whether a Hook requires a state worker. If it does, return true
  # otherwise return a false.
  defp requires_state?(%Hook{ provide: provide }) when is_list(provide),
    do: :cache in provide
  defp requires_state?(_hook),
    do: false
end
