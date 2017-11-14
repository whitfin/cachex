defmodule Cachex.Services.Janitor do
  @moduledoc false
  # The main TTL cleanup for Cachex, providing a very basic task scheduler to
  # repeatedly cleanup the cache table for all records which have expired. This
  # is a separate process to avoid any potential overhead in the main process.
  # It's possible that certain cleanups will result in full table scans, and so
  # we split into a separate GenServer for safety in case it takes a while.

  # use GenServer
  use GenServer

  # add some aliases
  alias Cachex.Services
  alias Cachex.State
  alias Cachex.Util

  # include services
  alias Services.Informant
  alias Services.Locksmith

  @doc """
  Simple initialization for use in the main owner process in order to start an
  instance of a janitor.

  All options are passed throught to the initialization function, and the GenServer
  options are passed straight to GenServer to deal with.
  """
  def start_link(%State{ } = state, server_opts) when is_list(server_opts),
    do: GenServer.start_link(__MODULE__, state, server_opts)

  @doc """
  Main initialization phase of a janitor.

  This will create a stats struct as required and create the initial state for
  this janitor. The state is then passed through for use in the future.
  """
  def init(%State{ } = state),
    do: { :ok, { schedule_check(state), %{ } } }

  @doc """
  Returns the last metadata for this Janitor.
  """
  def handle_call(:last, _ctx, { _state, last } = new_state),
    do: { :reply, last, new_state }

  @doc """
  Runs a TTL check and eviction against the backing ETS table.

  We basically drop to the ETS level and provide a select which only matches docs
  to be removed, and then ETS deletes them as it goes.
  """
  def handle_info(:ttl_check, { %State{ cache: cache }, _last }) do
    new_states = State.get(cache)
    start_time = Util.now()

    { duration, { :ok, count } = result } = :timer.tc(fn ->
      purge_records(new_states)
    end)

    if count > 0 do
      Informant.broadcast(new_states, { :purge, [ [] ] }, result)
    end

    last = %{
      count: count,
      duration: duration,
      started: start_time
    }

    { :noreply, { schedule_check(new_states), last } }
  end

  @doc """
  A public handler for purging records, so that it can be called from the main
  process as needed.

  This execution happens inside a Transaction to ensure that there are no open
  key locks on the table.
  """
  @spec purge_records(State.t) :: { :ok, integer }
  def purge_records(%State{ cache: cache } = state) do
    Locksmith.transaction(state, [ ], fn ->
      { :ok, :ets.select_delete(cache, Util.retrieve_expired_rows(true)) }
    end)
  end

  # Schedules a check to occur after the designated interval. Once scheduled,
  # returns the state - this is just sugar for pipelining with a state.
  defp schedule_check(%State{ ttl_interval: ttl_interval } = state) do
    :erlang.send_after(ttl_interval, self(), :ttl_check)
    state
  end
end
