defmodule Cachex.Stats do
  # use the hooks
  use Cachex.Hook

  # we need a Logger
  require Logger

  # add some aliases
  alias Cachex.Util

  @moduledoc false
  # A simple statistics container, used to keep track of various operations on
  # a given cache. This is used as a post hook for a cache and provides an example
  # of what a hook can look like. This container has no knowledge of the cache
  # it belongs to, it only keeps track of an internal struct.

  @amount_based MapSet.new([ :clear, :purge ])
  @status_based MapSet.new([ :get, :get_and_update, :expire, :expire_at, :persist, :refresh, :take, :ttl ])
  @values_based MapSet.new([ :set, :del, :exists?, :update ])

  @doc """
  Initializes a new stats container, setting the creation date to the current time.
  This state will be passed into each handler in this server.
  """
  def init(_options \\ []) do
    { :ok, add_meta(%{ }, :creationDate, Cachex.Util.now()) }
  end

  @doc """
  We don't keep statistics on requests which errored, to avoid false positives
  about what exactly is going on inside a given cache.
  """
  def handle_notify(action, { status, val }, stats) when status != :error do
    act = elem(action, 0)

    amount_based? = find_if_required(@amount_based, act, false)
    status_based? = find_if_required(@status_based, act, amount_based?)
    values_based? = find_if_required(@values_based, act, amount_based? || status_based?)

    set_value = cond do
      status_based? -> status
      values_based? -> val
      amount_based? -> :total
      true -> :calls
    end

    amount = cond do
      amount_based? -> val
      true -> 1
    end

    global_status = cond do
      status_based? ->
        case status do
          :ok ->
            [ :hitCount ]
          :missing ->
            [ :missCount ]
          :loaded ->
            [ :missCount, :loadCount ]
        end
      act == :exists? ->
        [ val == true && :hitCount || :missCount ]
      true ->
        [ ]
    end

    global_change = case act do
      action when action in [ :purge ] ->
        [ :expiredCount | global_status ]
      action when action in [ :del, :take, :clear ] ->
        [ :evictionCount | global_status ]
      action when action in [ :set, :get_and_update, :incr, :update ] ->
        [ :setCount | global_status ]
      _action ->
        global_status
    end

    stats
    |> increment(act, set_value, amount)
    |> increment(:global, global_change, amount)
    |> increment(:global, :opCount)
    |> Util.ok
  end

  @doc """
  Handles a call to retrieve the stats as they currently stand. We finalize the
  stats and return them to the calling process.
  """
  def handle_call({ :retrieve_stats, options }, stats) do
    normalized_options =
      options
      |> Keyword.get(:for, :global)
      |> List.wrap
      |> Enum.filter(&(&1 != :meta))

    finalized_stats = case normalized_options do
      [:raw] -> stats
      option -> finalize(stats, option)
    end

    { :ok, finalized_stats, stats }
  end

  @doc """
  Retrieves the stats for a given cache. This is simply shorthand for firing off
  a request to the stats hook. We provide it to make it more obvious to retrieve
  statistics.
  """
  def retrieve(stats_ref, options \\ []) do
    GenEvent.call(stats_ref, __MODULE__, { :retrieve_stats, options })
  end

  # Adds a metadata key to the cache statistics. This is just a simple get/set
  # and doesn't provide increments because this contains things just as dates.
  defp add_meta(%{ :meta => meta } = stats, key, val) do
    Map.put(stats, :meta, Map.put(meta, key, val))
  end
  defp add_meta(%{ } = stats, key, val) do
    stats
    |> Map.put(:meta, %{ })
    |> add_meta(key, val)
  end

  # Finalizes the stats to be returned in some form. Asking for different keys
  # provides you with various bonus statistics about those keys. If you don't
  # ask for anything specific, you get a high level overview about what's in the
  # cache.
  defp finalize(stats, options) when is_list(options) do
    options
    |> Enum.map(fn(option) ->
        case Map.get(stats, option) do
          nil ->
            Map.put(%{ }, option, %{ })
          val ->
            finalized_stats =
              val
              |> finalize(option)

            case option do
              :global ->
                finalized_stats
              _others ->
                Map.put(%{ }, option, finalized_stats)
            end
        end
       end)
    |> Enum.reduce(%{}, &(Map.merge(&2, &1)))
    |> Map.merge(Map.get(stats, :meta))
  end
  defp finalize(stats, :global) do
    hitCount = Map.get(stats, :hitCount, 0)
    missCount = Map.get(stats, :missCount, 0)
    loadCount = Map.get(stats, :loadCount, 0)

    totalMissCount = missCount + loadCount

    reqRates = case hitCount + totalMissCount do
      0 ->
        %{ requestCount: 0 }
      v ->
        cond do
          hitCount == 0 -> %{
            requestCount: v,
            hitRate: 0,
            missRate: 100
          }
          missCount == 0 -> %{
            requestCount: v,
            hitRate: 100,
            missRate: 0
          }
          true -> %{
            requestCount: v,
            hitRate: hitCount / v,
            missRate: totalMissCount / v
          }
        end
    end

    stats
    |> Map.merge(reqRates)
    |> Enum.sort(&(elem(&1, 0) > elem(&2, 0)))
    |> Enum.into(%{})
  end
  defp finalize(stats, option) do
    Map.has_key?(stats, option) && stats[option] || stats
  end

  # Looks inside a set for a value assuming it's required to still look for it.
  # This is just sugar to normalize some of the unnecessary searches done in the
  # event handlers defined above.
  defp find_if_required(_set, _val, true), do: false
  defp find_if_required(set, val, _required?), do: MapSet.member?(set, val)

  # Increments a given set of statistics by a given amount. If the amount is not
  # provided, we default to a value of 1. We accept a list of fields to work with
  # as it's not unusual for an action to increment various fields at the same time.
  defp increment(stats, action, fields, amount \\ 1) do
    action_stats =
      stats
      |> Map.get(action, %{ })

    new_action_stats =
      fields
      |> List.wrap
      |> Enum.reduce(action_stats, &(Map.put(&2, &1, Map.get(&2, &1, 0) + amount)))

    Map.put(stats, action, new_action_stats)
  end

end
