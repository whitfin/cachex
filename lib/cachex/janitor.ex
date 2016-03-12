defmodule Cachex.Janitor do
  # use Macros and GenServer
  use Cachex.Macros.GenServer
  use GenServer

  # import utils for convenience
  import Cachex.Util

  @moduledoc false
  # The main TTL cleanup for Cachex, providing a very basic task scheduler to
  # repeatedly cleanup the cache table for all records which have expired. This
  # is a separate process to avoid any potential overhead in the main process.
  # It's possible that certain cleanups will result in full table scans, and so
  # we split into a separate GenServer for safety in case it takes a while.

  defstruct cache: nil,         # the name of the cache
            interval: nil,      # the interval to check the ttl
            stats_ref: nil      # a reference to send stats to

  @doc """
  Simple initialization for use in the main owner process in order to start an
  instance of a janitor. All options are passed throught to the initialization
  function, and the GenServer options are passed straight to GenServer to deal
  with.
  """
  def start_link(options \\ %Cachex.Options { }, gen_options \\ []) do
    GenServer.start(__MODULE__, options, gen_options)
  end

  @doc """
  Main initialization phase of a janitor, creating a stats struct as required and
  creating the initial state for this janitor. The state is then passed through
  for use in the future.
  """
  def init(options \\ %Cachex.Options { }) do
    state = %__MODULE__{
      cache: options.cache,
      interval: options.ttl_interval,
      stats_ref: Hook.ref_by_module(options.post_hooks, Cachex.Stats)
    }
    { :ok, schedule_check(state) }
  end

  @doc """
  The only code which currently runs within this process, the ttl check. This
  function is black magic and potentially needs to be improved, but it's super
  fast (the best perf I've seen). We basically drop to the ETS level and provide
  a select which only matches docs to be removed, and then ETS deletes them as it
  goes.
  """
  definfo ttl_check do
    state.cache
    |> purge_records

    state
    |> schedule_check
    |> noreply
  end

  @doc """
  A public handler for purging records, so that it can be called from the main
  process as needed. This is needed because we expose purging in the public API.
  """
  def purge_records(cache) when is_atom(cache) do
    expired_count =
      cache
      |> :ets.select_delete(create_selection(true))

    cache
    |> update_evictions(expired_count)
  end

  # Returns a selection to return the designated values, just an easier way to
  # define this in one place - not the nicest piece in the world.
  defp create_selection(return) do
    [
      {
        { :"_", :"$1", :"$2", :"$3", :"_" },        # input (our records)
        [
          {
            :andalso,                               # guards for matching
            { :"/=", :"$3", nil },                  # where a TTL is set
            { :"<", { :"+", :"$2", :"$3" }, now }   # and the TTL has passed
          }
        ],
        [ return ]                                  # our output
      }
    ]
  end

  # Schedules a check to occur after the designated interval. Once scheduled,
  # returns the state - this is just sugar for pipelining with a state.
  defp update_evictions(cache, evictions) do
    GenServer.cast(cache, { :record_purge, evictions })
    { :ok, evictions }
  end

  # Schedules a check to occur after the designated interval. Once scheduled,
  # returns the state - this is just sugar for pipelining with a state.
  defp schedule_check(state) do
    :erlang.send_after(state.interval, self, :ttl_check)
    state
  end

end
