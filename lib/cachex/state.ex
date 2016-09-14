defmodule Cachex.State do
  @moduledoc false
  # This module controls the state of caches being handled by Cachex. This is part
  # of an experiment to see if it's viable to remove the internal GenServer to
  # avoid several bottleneck scenarios, at well as letting the developer choose
  # how to control their concurrency.
  #
  # States are stored inside an ETS table which is started via `Cachex.Application`
  # and should only be accessed via this module. The interface is deliberately
  # small in order to reduce potential complexity.

  # internal state struct
  defstruct cache: nil,             # the name of the cache
            disable_ode: false,     # whether we disable on-demand expiration
            ets_opts: nil,          # any options to give to ETS
            default_ttl: nil,       # any default ttl values to use
            fallback: nil,          # the default fallback implementation
            fallback_args: nil,     # arguments to pass to a cache loader
            janitor: nil,           # the name of the janitor attached (if any)
            limit: nil,             # any limit to apply to the cache
            manager: nil,           # the name of the manager attached
            pre_hooks: nil,         # any pre hooks to attach
            post_hooks: nil,        # any post hooks to attach
            transactions: nil,      # whether to enable transactions
            ttl_interval: nil       # the ttl check interval

  # add any aliases
  alias Cachex.Hook
  alias Supervisor.Spec

  # our opaque type
  @opaque t :: %__MODULE__{ }

  # name of internal table
  @state_table :cachex_state_table

  # transaction manager
  @transaction_manager :cachex_state_manager

  @doc false
  def start_link do
    ets_opts = [
      read_concurrency: true,
      write_concurrency: true
    ]

    children = [
      Spec.supervisor(Eternal, [ @state_table, ets_opts, [ quiet: true ] ]),
      Spec.worker(Agent, [ fn -> :ok end, [ name: @transaction_manager ] ])
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: :cachex_state)
  end

  @doc """
  Removes a state from the local state table.
  """
  @spec del(cache :: atom) :: true
  def del(cache) when is_atom(cache) do
    :ets.delete(@state_table, cache)
  end

  @doc """
  Retrieves a state from the local state table, or `nil` if none exists.
  """
  @spec get(cache :: atom) :: state :: State.t | nil
  def get(cache) when is_atom(cache) do
    case :ets.lookup(@state_table, cache) do
      [{ ^cache, state }] ->
        state
      _other ->
        nil
    end
  end

  @doc """
  Determines whether the given cache is provided in the state table.
  """
  @spec member?(cache :: atom) :: true | false
  def member?(cache) when is_atom(cache) do
    :ets.member(@state_table, cache)
  end

  @doc """
  Sets a state in the local state table.
  """
  @spec set(cache :: atom, state :: State.t) :: true
  def set(cache, %__MODULE__{ } = state) when is_atom(cache) do
    :ets.insert(@state_table, { cache, state })
  end

  @doc """
  Determines whether the tables for this module have been setup correctly.
  """
  @spec setup? :: true | false
  def setup? do
    Enum.member?(:ets.all, @state_table)
  end

  @doc """
  Returns the name of the local state table.
  """
  @spec table_name :: table_name :: atom
  def table_name do
    @state_table
  end

  @doc """
  Carries out a blocking set of actions against the state table.
  """
  @spec transaction(cache :: atom, function :: fun) :: any
  def transaction(cache, fun) when is_atom(cache) and is_function(fun, 0) do
    Agent.get(@transaction_manager, fn(state) ->
      try do
        fun.()
      rescue
        _ -> state
      end
    end)
  end

  @doc """
  Updates a state inside the local state table.

  This is atomic and happens inside a transaction to ensure that we don't get
  out of sync. Hooks are notified of the change, and the new state is returned.
  """
  @spec update(cache :: atom, function :: (State.t -> State.t)) :: state :: State.t
  def update(cache, fun) when is_atom(cache) and is_function(fun, 1) do
    transaction(cache, fn ->
      cstate = get(cache)
      nstate = fun.(cstate)

      set(cache, nstate)

      nstate.pre_hooks
      |> Enum.concat(nstate.post_hooks)
      |> Enum.filter(&requires_worker?/1)
      |> Enum.each(&send(&1.ref, { :provision, { :worker, nstate } }))

      nstate
    end)
  end

  defp requires_worker?(%Hook{ provide: provide }) when is_list(provide) do
    :worker in provide
  end
  defp requires_worker?(_hook) do
    false
  end

end
