defmodule Cachex.Janitor do
  use Cachex.Macros
  use GenServer
  require Qlc

  @moduledoc false
  # The main TTL cleanup for Cachex, providing a very basic task scheduler to
  # repeatedly cleanup the cache table for all records which have expired. This
  # is a separate process to avoid any potential overhead in the main process.
  # It's possible that certain cleanups will result in full table scans, and so
  # we split into a separate GenServer for safety in case it takes a while.

  defstruct cache: nil,     # the name of the cache
            interval: nil   # the interval to check the ttl

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
      interval: options.ttl_interval
    }
    { :ok, schedule_check(state) }
  end

  @doc """
  The only code which currently runs within this process, the ttl check. This
  function will iterate and fetch all keys for which the expiry time has passed.
  It will then proceed to delete all of these values in a single context to
  avoid repeatedly opening a handle to the backing table. Finally, we schedule
  this function to be called again after the interval has passed.
  """
  definfo ttl_check do
    :mnesia.transaction(fn ->
      "[K || {_,K,E,_} <- C, E /= nil, E < N]"
      |> Qlc.q([ C: :mnesia.table(state.cache), N: :os.system_time(1000) ])
      |> Qlc.e
      |> Enum.each(&(:mnesia.delete({ state.cache, &1 })))
    end)

    state
    |> schedule_check
    |> noreply
  end

  # Schedules a check to occur after the designated interval. Once scheduled,
  # returns the state - this is just sugar for pipelining with a state.
  defp schedule_check(state) do
    :erlang.send_after(state.interval, self, :ttl_check)
    state
  end

end
