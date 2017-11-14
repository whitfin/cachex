defmodule Cachex.Cache do
  @moduledoc false
  # This module controls the state of caches being handled by Cachex. This is part
  # of an experiment to see if it's viable to remove the internal GenServer to
  # avoid several bottleneck scenarios, at well as letting the developer choose
  # how to control their concurrency.
  #
  # States are stored inside an ETS table which is started via `Cachex.Application`
  # and should only be accessed via this module. The interface is deliberately
  # small in order to reduce potential complexity.

  # grab constants
  use Cachex.Constants

  # add any aliases
  alias Cachex.Cache
  alias Cachex.Fallback
  alias Cachex.Hook
  alias Cachex.Limit
  alias Supervisor.Spec

  # internal state struct
  defstruct name: nil,              # the name of the cache
            commands: %{},          # any custom commands attached to the cache
            ets_opts: [],           # any options to give to ETS
            default_ttl: nil,       # any default ttl values to use
            fallback: %Fallback{},  # the default fallback implementation
            janitor: nil,           # the name of the janitor attached (if any)
            limit: %Limit{},        # any limit to apply to the cache
            locksmith: nil,         # the name of the locksmith queue attached
            ode: true,              # whether we enable on-demand expiration
            pre_hooks: [],          # any pre hooks to attach
            post_hooks: [],         # any post hooks to attach
            transactions: false,    # whether to enable transactions
            ttl_interval: nil       # the ttl check interval

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
  Enforces a cache binding into a given state.

  If the cache cannot be coerced into the given state, a nil value is returned.
  If it can be coerced, the body is unquoted and executed.
  """
  defmacro enforce(name, cache, do: body) do
    quote do
      case Cache.ensure(unquote(name)) do
        nil ->
          @error_no_cache
        unquote(cache) ->
          if :erlang.whereis(unquote(cache).name) != :undefined do
            unquote(body)
          else
            @error_no_cache
          end
      end
    end
  end

  @doc """
  Removes a state from the local state table.
  """
  @spec del(atom) :: true
  def del(name) when is_atom(name),
    do: :ets.delete(@state_table, name)

  @doc """
  Ensures a state from a cache name or state.
  """
  @spec ensure(atom | Cache.t) :: Cache.t | nil
  def ensure(%__MODULE__{ } = cache),
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
    case :ets.lookup(@state_table, name) do
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
    do: :ets.member(@state_table, name)

  @doc """
  Sets a state in the local state table.
  """
  @spec set(atom, Cache.t) :: true
  def set(name, %__MODULE__{ } = cache) when is_atom(name),
    do: :ets.insert(@state_table, { name, cache })

  @doc """
  Determines whether the tables for this module have been setup correctly.
  """
  @spec setup? :: true | false
  def setup?,
    do: Enum.member?(:ets.all, @state_table)

  @doc """
  Returns the name of the local state table.
  """
  @spec table_name :: atom
  def table_name,
    do: @state_table

  @doc """
  Carries out a blocking set of actions against the state table.
  """
  @spec transaction(atom, ( -> any)) :: any
  def transaction(name, fun) when is_atom(name) and is_function(fun, 0) do
    Agent.get(@transaction_manager, fn(cache) ->
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

      nstate.pre_hooks
      |> Enum.concat(nstate.post_hooks)
      |> Enum.filter(&requires_worker?/1)
      |> Enum.each(&send(&1.ref, { :provision, { :worker, nstate } }))

      nstate
    end)
  end
  def update(name, %__MODULE__{ } = cache) when is_atom(name),
    do: update(name, fn _ -> cache end)

  # Verifies whether a Hook requires a state worker. If it does, return true
  # otherwise return a false.
  defp requires_worker?(%Hook{ provide: provide }) when is_list(provide),
    do: :worker in provide
  defp requires_worker?(_hook),
    do: false
end
