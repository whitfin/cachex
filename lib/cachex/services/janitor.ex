defmodule Cachex.Services.Janitor do
  @moduledoc false
  # Expiration service to clean up expired cache records periodically.
  #
  # The Janitor provides the main expiration cleanup for Cachex, providing a
  # very basic scheduler to repeatedly cleanup cache tables for all expired
  # entries.
  #
  # This runs in a separate process to avoid any potential overhead in for
  # a user, but uses existing functions in the API so manual cleanup is
  # possible. It's possible that certain cleanups will result in full table
  # scans, so it should be expected that this can take a while to execute.
  use GenServer
  use Cachex.Provision

  # import parent macros
  import Cachex.Error
  import Cachex.Spec

  # add some aliases
  alias Cachex.Query

  ##############
  # Public API #
  ##############

  @doc """
  Starts a new Janitor process for a cache.

  At this point customization is non-existent, in order to keep the service
  as simple as possible and avoid the space for error and edge cases.
  """
  @spec start_link(Cachex.t()) :: GenServer.on_start()
  def start_link(cache(name: name) = cache),
    do: GenServer.start_link(__MODULE__, cache, name: name(name, :janitor))

  @doc """
  Pulls an expiration associated with an entry.
  """
  @spec expiration(Cachex.t(), integer | nil) :: integer
  def expiration(cache(expiration: expiration(default: default)), nil),
    do: default

  def expiration(_cache, expiration),
    do: expiration

  @doc """
  Determines if a cache entry has expired.

  This will take cache lazy expiration settings into account.
  """
  @spec expired?(Cachex.t(), Cachex.Spec.entry()) :: boolean
  def expired?(cache(expiration: expiration(lazy: lazy)), entry() = entry),
    do: lazy and expired?(entry)

  @doc """
  Determines if a cache entry has expired.

  This will not cache lazy expiration settings into account.
  """
  @spec expired?(Cachex.Spec.entry()) :: boolean
  def expired?(entry(modified: modified, expiration: exp)) when is_number(exp),
    do: modified + exp < now()

  def expired?(_entry),
    do: false

  @doc """
  Retrieves information about the latest Janitor run for a cache.

  If the service is disabled on the cache, an error is returned.
  """
  @spec last_run(Cachex.t()) :: %{}
  def last_run(cache(expiration: expiration(interval: nil))),
    do: error(:janitor_disabled)

  def last_run(cache() = cache),
    do: service_call(cache, :janitor, :last)

  ####################
  # Server Callbacks #
  ####################

  @doc false
  # Initializes a Janitor service using a cache record.
  #
  # This will create the structure used to store metadata about
  # the run cycles of the Janitor, and schedule the first run.
  def init(_),
    do: {:ok, {nil, nil}}

  @doc false
  # Defines provisions required by this service.
  def provisions,
    do: [:cache]

  @doc false
  # Returns metadata about the last run of this Janitor.
  #
  # The returned information should be treated as non-guaranteed.
  def handle_call(:last, _ctx, {_cache, last} = state),
    do: {:reply, {:ok, last}, state}

  @doc false
  # Executes an expiration cleanup against a cache table.
  #
  # This will drop to the ETS level and use a select to match documents which
  # need to be removed; they are then deleted by ETS at very high speeds.
  def handle_info(:purge, {cache, _last}) do
    started = now()
    options = const(:local) ++ const(:notify_false)

    {duration, count} =
      :timer.tc(fn ->
        query =
          Query.build(
            where: {:not, {:==, :expiration, nil}},
            output: true,
            buffer: 1
          )

        cache
        |> Cachex.stream!(query, options)
        |> Enum.empty?()
        |> handle_skip_check(cache)
      end)

    last = %{
      count: count,
      started: started,
      duration: duration
    }

    {:noreply, {schedule(cache), last}}
  end

  @doc false
  # Receives a provisioned cache instance.
  #
  # The provided cache is then stored in the state and used for cache calls going
  # forwards, in order to skip the lookups inside the cache overseer for performance.
  def handle_provision({:cache, cache}, {nil, last}),
    do: {:ok, {schedule(cache), last}}

  def handle_provision({:cache, cache}, {_cache, last}),
    do: {:ok, {cache, last}}

  ###############
  # Private API #
  ###############

  # Handle check for purge skipping, if no skip run purge.
  defp handle_skip_check(false, cache),
    do: Cachex.purge(cache, const(:local))

  defp handle_skip_check(true, _cache),
    do: 0

  # Schedules a check to occur after the designated interval. Once scheduled,
  # returns the state - this is just sugar for pipelining with a state.
  defp schedule(cache(expiration: expiration(interval: interval)) = cache) do
    :erlang.send_after(interval, self(), :purge)
    cache
  end
end
