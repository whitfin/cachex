defmodule Cachex.Janitor do
  @moduledoc false
  # The main TTL cleanup for Cachex, providing a very basic task scheduler to
  # repeatedly cleanup the cache table for all records which have expired. This
  # is a separate process to avoid any potential overhead in the main process.
  # It's possible that certain cleanups will result in full table scans, and so
  # we split into a separate GenServer for safety in case it takes a while.

  # use GenServer
  use GenServer

  # add some aliases
  alias Cachex.Hook
  alias Cachex.LockManager
  alias Cachex.State
  alias Cachex.Util

  # define our struct
  defstruct cache: nil,         # the name of the cache
            interval: nil,      # the interval to check the ttl
            last: %{}           # information stored about the last run

  @doc """
  Simple initialization for use in the main owner process in order to start an
  instance of a janitor.

  All options are passed throught to the initialization function, and the GenServer
  options are passed straight to GenServer to deal with.
  """
  def start_link(%State{ } = state, server_opts) when is_list(server_opts) do
    GenServer.start_link(__MODULE__, state, server_opts)
  end

  @doc """
  Main initialization phase of a janitor.

  This will create a stats struct as required and create the initial state for
  this janitor. The state is then passed through for use in the future.
  """
  def init(%State{ cache: cache, ttl_interval: ttl_interval }) do
    state = %__MODULE__{
      cache: cache,
      interval: ttl_interval
    }
    { :ok, schedule_check(state) }
  end

  @doc """
  Returns the last metadata for this Janitor.
  """
  def handle_call(:last, _ctx, %__MODULE__{ last: last } = state) do
    { :reply, last, state }
  end

  @doc """
  Runs a TTL check and eviction against the backing ETS table.

  We basically drop to the ETS level and provide a select which only matches docs
  to be removed, and then ETS deletes them as it goes.
  """
  def handle_info(:ttl_check, %__MODULE__{ cache: cache } = state) do
    start_time = Util.now()

    { duration, result } = :timer.tc(fn ->
      purge_records(cache)
    end)

    new_state =
      result
      |> update_evictions(state)
      |> schedule_check
      |> update_meta(start_time, duration, result)

    { :noreply, new_state }
  end

  @doc """
  A public handler for purging records, so that it can be called from the main
  process as needed.

  This execution happens inside a Transaction to ensure that there are no open
  key locks on the table.
  """
  def purge_records(cache) when is_atom(cache) do
    case State.get(cache) do
      nil -> false
      val -> purge_records(val)
    end
  end
  def purge_records(%State{ cache: cache } = state) do
    LockManager.transaction(state, [ ], fn ->
      { :ok, :ets.select_delete(cache, Util.retrieve_expired_rows(true)) }
    end)
  end

  # Broadcasts the number of evictions against this purge in order to notify any
  # hooks that a purge has just occurred.
  defp update_evictions({ :ok, evictions } = result, state) when evictions > 0 do
    Hook.broadcast(state.cache, { :purge, [ [] ] }, result)
    state
  end
  defp update_evictions(_other, state), do: state

  # Schedules a check to occur after the designated interval. Once scheduled,
  # returns the state - this is just sugar for pipelining with a state.
  defp schedule_check(%__MODULE__{ interval: interval } = state) do
    :erlang.send_after(interval, self(), :ttl_check)
    state
  end

  # Updates the metadata of this cache, keeping track of various things about the
  # last run sequence. Currently we only keep track of the number of previous
  # evictions, the duration of the eviction run, and the start time of the run.
  defp update_meta(state, start_time, duration, { :ok, count }) do
    new_last = %{
      count: count,
      duration: duration,
      started: start_time
    }
    %__MODULE__{ state | last: new_last }
  end

end
