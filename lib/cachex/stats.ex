defmodule Cachex.Stats do
  # use Macros and Hook
  use Cachex.Hook
  use Cachex.Macros.Stats

  @moduledoc false
  # A simple statistics container, used to keep track of various operations on
  # a given cache. This is used as a post hook for a cache and provides an example
  # of what a hook can look like. This container has no knowledge of the cache
  # it belongs to, it only keeps track of an internal struct.

  defstruct opCount: 0,         # number of operations on the cache
            setCount: 0,        # number of keys set on the cache
            hitCount: 0,        # number of times a found key was asked for
            missCount: 0,       # number of times a missing key was asked for
            loadCount: 0,       # number of times a key was loaded
            evictionCount: 0,   # number of deletions on the cache
            expiredCount: 0,    # number of documents expired due to TTL
            creationDate: nil   # the date this cache was initialized

  @doc """
  Initializes a new stats container, setting the creation date to the current time.
  This state will be passed into each handler in this server.
  """
  def init(_options \\ []) do
    { :ok, %__MODULE__{ creationDate: Cachex.Util.now() } }
  end

  @doc """
  Add a cache hit, as a found value was retrieved from the cache.
  """
  def handle_notify({ :get, _key, _options }, { :ok, _val }, stats) do
    { :ok, increment(stats, [:opCount, :hitCount]) }
  end

  @doc """
  Add a cache miss, as a nil value was retrieved from the cache.
  """
  def handle_notify({ :get, _key, _options }, { :missing, nil }, stats) do
    { :ok, increment(stats, [:opCount, :missCount]) }
  end

  @doc """
  Add a cache miss, and also increment the load count.
  """
  def handle_notify({ :get, _key, _options }, { :loaded, _val }, stats) do
    { :ok, increment(stats, [:opCount, :missCount, :loadCount]) }
  end

  @doc """
  Add a set operation, as a key/value was set in the cache.
  """
  def handle_notify({ :set, _key, _value, _options }, _result, stats) do
    { :ok, increment(stats, [:opCount, :setCount]) }
  end

  @doc """
  Add evictions to the stats, using the amount provided in the results.
  """
  def handle_notify({ :clear, _options }, { :ok, amount }, stats) do
    { :ok, increment(stats, [:opCount, :evictionCount], amount) }
  end

  @doc """
  Add a hit to show that the key existed.
  """
  def handle_notify({ :exists?, _key, _options }, { :ok, true }, stats) do
    { :ok, increment(stats, [:opCount, :hitCount]) }
  end

  @doc """
  Add a miss to show that the key did not exist.
  """
  def handle_notify({ :exists?, _key, _options }, { :ok, false }, stats) do
    { :ok, increment(stats, [:opCount, :missCount]) }
  end

  @doc """
  Add evictions to the stats, using the amount provided in the results.
  """
  def handle_notify({ :purge, _options }, { :ok, amount }, stats) do
    { :ok, increment(stats, [:opCount, :evictionCount], amount) }
  end

  @doc """
  Add an eviction to the stats, representing the delete operation.
  """
  def handle_notify({ :del, _key, _options }, _result, stats) do
    { :ok, increment(stats, [:opCount, :evictionCount]) }
  end

  @doc """
  Add a cache miss, as taking a value from the cache did not retrieve a value.
  We do not add a cache eviction, as the value did not exist.
  """
  def handle_notify({ :take, _key, _options }, { :ok, nil }, stats) do
    { :ok, increment(stats, [:opCount, :missCount]) }
  end

  @doc """
  Add a cache hit, as taking a value from the cache returned a value. We also add
  a cache eviction as the value is now removed.
  """
  def handle_notify({ :take, _key, _options }, { :ok, _val }, stats) do
    { :ok, increment(stats, [:opCount, :hitCount, :evictionCount]) }
  end

  @doc """
  Various states which need to be swallowed to avoid incrementing stats.
  """
  defswallow swallow({ :expire, _key, _ttl, _options }, { :error, _ })
  defswallow swallow({ :expire_at, _key, _date, _options }, _result)
  defswallow swallow({ :persist, _key, _options }, _result)
  defswallow swallow({ :refresh, _key, _options }, { :error, _ })

  @doc """
  For all operations which are not specifically handled, we add an operation to
  the stats container. This is basically just a catch-all to make sure operations
  are represented in some way.
  """
  def handle_notify(_, _result, stats) do
    { :ok, increment(stats, [:opCount]) }
  end

  @doc """
  Handles a call to retrieve the stats as they currently stand. We finalize the
  stats and return them to the calling process.
  """
  def handle_call(:retrieve_stats, stats) do
    { :ok, finalize(stats), stats }
  end

  @doc """
  Retrieves the stats for a given cache. This is simply shorthand for firing off
  a request to the stats hook. We provide it to make it more obvious to retrieve
  statistics.
  """
  def retrieve(stats_ref) do
    GenEvent.call(stats_ref, __MODULE__, :retrieve_stats)
  end

  # Increments a given set of statistics by a given amount. If the amount is not
  # provided, we default to a value of 1. We accept a list of fields to work with
  # as it's not unusual for an action to increment various fields at the same time.
  defp increment(stats, fields, amount \\ 1) do
    fields
    |> List.wrap
    |> Enum.reduce(stats, fn(field, stats) ->
        Map.put(stats, field, Map.get(stats, field, 0) + amount)
       end)
  end

  # Finalizes the struct into a Map containing various fields we can deduce from
  # the struct. The bonus fields are why we don't just return the struct - there's
  # no need to store these in the struct all the time, they're only needed once.
  defp finalize(%__MODULE__{ } = stats_struct) do
    reqRates = case stats_struct.hitCount + stats_struct.missCount do
      0 ->
        %{ "requestCount": 0 }
      v ->
        cond do
          stats_struct.hitCount == 0 -> %{
            "requestCount": v,
            "hitRate": 0,
            "missRate": 100
          }
          stats_struct.missCount == 0 -> %{
            "requestCount": v,
            "hitRate": 100,
            "missRate": 0
          }
          true -> %{
            "requestCount": v,
            "hitRate": stats_struct.hitCount / v,
            "missRate": stats_struct.missCount / v
          }
        end
    end

    stats_struct
    |> Map.from_struct
    |> Map.merge(reqRates)
    |> Enum.sort(&(elem(&1, 0) > elem(&2, 0)))
    |> Enum.into(%{})
  end

end
