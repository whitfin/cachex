defmodule Cachex.Janitor do
  # use GenServer
  use GenServer

  # import utils for convenience
  import Cachex.Util

  # add a worker alias
  alias Cachex.Worker

  @moduledoc false
  # The main TTL cleanup for Cachex, providing a very basic task scheduler to
  # repeatedly cleanup the cache table for all records which have expired. This
  # is a separate process to avoid any potential overhead in the main process.
  # It's possible that certain cleanups will result in full table scans, and so
  # we split into a separate GenServer for safety in case it takes a while.

  defstruct cache: nil,         # the name of the cache
            interval: nil,      # the interval to check the ttl
            last: %{}           # information stored about the last run

  @doc """
  Simple initialization for use in the main owner process in order to start an
  instance of a janitor. All options are passed throught to the initialization
  function, and the GenServer options are passed straight to GenServer to deal
  with.
  """
  def start_link(options \\ %Cachex.Options { }, gen_options \\ []) do
    if options.ttl_interval do
      GenServer.start_link(__MODULE__, options, gen_options)
    end
  end

  @doc """
  Main initialization phase of a janitor, creating a stats struct as required and
  creating the initial state for this janitor. The state is then passed through
  for use in the future.
  """
  def init(options \\ %Cachex.Options { }) do
    state = %__MODULE__{
      cache: options.cache,
      interval: options.ttl_interval
    }
    { :ok, schedule_check(state) }
  end

  @doc """
  Simply plucks and returns the last metadata for this Janitor.
  """
  def handle_call(:last, _ctx, state) do
    { :reply, state.last, state }
  end

  @doc """
  The only code which currently runs within this process, the ttl check. This
  function is black magic and potentially needs to be improved, but it's super
  fast (the best perf I've seen). We basically drop to the ETS level and provide
  a select which only matches docs to be removed, and then ETS deletes them as it
  goes.
  """
  def handle_info(:ttl_check, state) do
    start_time = now()

    { duration, result } = :timer.tc(fn ->
      purge_records(state.cache)
    end)

    result
    |> update_evictions(state)
    |> schedule_check
    |> update_meta(start_time, duration, result)
    |> noreply
  end

  @doc """
  A public handler for purging records, so that it can be called from the main
  process as needed. This is needed because we expose purging in the public API.
  """
  def purge_records(cache) when is_atom(cache) do
    { :ok, :ets.select_delete(cache, retrieve_expired_rows(true)) }
  end

  # Broadcasts the number of evictions against this purge in order to notify any
  # hooks that a purge has just occurred.
  defp update_evictions({ :ok, evictions } = result, state) when evictions > 0 do
    Worker.broadcast(state.cache, { :purge, [] }, result)
    state
  end
  defp update_evictions(_other, state), do: state

  # Schedules a check to occur after the designated interval. Once scheduled,
  # returns the state - this is just sugar for pipelining with a state.
  defp schedule_check(state) do
    :erlang.send_after(state.interval, self, :ttl_check)
    state
  end

  # Updates the metadata of this cache, keeping track of various things about the
  # last run sequence.
  defp update_meta(state, start_time, duration, { :ok, count }) do
    new_last = %{
      count: count,
      duration: duration,
      started: start_time
    }
    %__MODULE__{ state | last: new_last }
  end

end
