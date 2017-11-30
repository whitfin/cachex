defmodule Cachex.Services.Janitor do
  @moduledoc false
  # The main TTL cleanup for Cachex, providing a very basic task scheduler to
  # repeatedly cleanup the cache table for all records which have expired. This
  # is a separate process to avoid any potential overhead in the main process.
  # It's possible that certain cleanups will result in full table scans, and so
  # we split into a separate GenServer for safety in case it takes a while.

  # use GenServer
  use GenServer

  # import parents
  import Cachex.Spec

  # add some aliases
  alias Cachex.Services
  alias Services.Informant
  alias Services.Overseer

  @doc """
  Simple initialization for use in the main owner process in order to start an
  instance of a janitor.

  All options are passed throught to the initialization function, and the GenServer
  options are passed straight to GenServer to deal with.
  """
  def start_link(cache(name: name) = cache),
    do: GenServer.start_link(__MODULE__, cache, [ name: name(name, :janitor) ])

  @doc """
  Main initialization phase of a janitor.

  This will create a stats struct as required and create the initial state for
  this janitor. The state is then passed through for use in the future.
  """
  def init(cache() = cache),
    do: { :ok, { schedule_check(cache), %{ } } }

  @doc """
  Returns the last metadata for this Janitor.
  """
  def handle_call(:last, _ctx, { _cache, last } = state),
    do: { :reply, last, state }

  @doc """
  Runs a TTL check and eviction against the backing ETS table.

  We basically drop to the ETS level and provide a select which only matches docs
  to be removed, and then ETS deletes them as it goes.
  """
  def handle_info(:ttl_check, { cache(name: name), _last }) do
    new_caches = Overseer.get(name)
    start_time = now()

    { duration, { :ok, count } = result } = :timer.tc(fn ->
      Cachex.purge(new_caches)
    end)

    if count > 0 do
      Informant.broadcast(new_caches, { :purge, [ [] ] }, result)
    end

    last = %{
      count: count,
      duration: duration,
      started: start_time
    }

    { :noreply, { schedule_check(new_caches), last } }
  end


  # Schedules a check to occur after the designated interval. Once scheduled,
  # returns the state - this is just sugar for pipelining with a state.
  defp schedule_check(cache(expiration: expiration(interval: interval)) = cache) do
    :erlang.send_after(interval, self(), :ttl_check)
    cache
  end
end
