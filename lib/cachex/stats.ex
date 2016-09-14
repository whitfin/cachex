defmodule Cachex.Stats do
  @moduledoc false
  # Controls the registration of new actions taken inside the cache. This is moved
  # outside due to the use of `process_action/2` which is defined many times to
  # match against actions efficiently.

  # add some aliases
  alias Cachex.Util

  @doc """
  Registers an action with the stats, incrementing various fields as appropriate
  and incrementing the global statistics map. Every action will increment the
  global operation count, but all other changes are action-specific.
  """
  @spec register(action :: { }, result :: { }, stats :: %{ }) :: %{ }
  def register(action, result, stats \\ %{ }) do
    action
    |> process_action(result)
    |> Enum.reduce(stats, &increment/2)
    |> increment(:global, :opCount)
  end

  # Clearing a cache returns the number of entries removed, so we update both the
  # total cleared as well as the global eviction count.
  defp process_action(:clear, { _status, value }) do
    [ { :clear, :total, value }, { :global, :evictionCount, value } ]
  end

  # Deleting a key should increment the delete count by 1 and the global eviction
  # count by 1.
  defp process_action(:del, { _status, value }) do
    [ { :del, value, 1 } ] ++ if value do
      [ { :global, :evictionCount, 1 } ]
    else
      []
    end
  end

  # Checking if a key exists simply updates the global hit/miss count based on
  # the value (which returns true or false depending on existence).
  defp process_action(:exists?, { _status, value }) do
    [ { :exists?, value, 1 } ] ++ if value do
      [ { :global, :hitCount,  1 } ]
    else
      [ { :global, :missCount, 1 } ]
    end
  end

  # Retrieving a value will increment the global stats to represent whether the
  # key existed, was missing, or was loaded.
  defp process_action(:get, { status, _value }) do
    [ { :get, status, 1 }, { :global, normalize_status(status), 1 } ]
  end

  # Purging receives the number of keys removed from the cache, so we use this
  # number to increment the exiredCount in the global namespace.
  defp process_action(:purge, { _status, value }) do
    [ { :purge, :total, value }, { :global, :expiredCount, value } ]
  end

  # Sets always update the global namespace and the setCount key.
  defp process_action(:set, { _status, value }) do
    [ { :set, value, 1 } ] ++ if value do
      [ { :global, :setCount, 1 } ]
    else
      []
    end
  end

  # Taking a key will update evictions if they exist, otherwise they'll just update
  # the same stats as if :get were called.
  defp process_action(:take, { status, _value }) do
    [ { :take, status, 1 }, { :global, normalize_status(status), 1 } ] ++ if status == :ok do
      [ { :global , :evictionCount, 1 } ]
    else
      []
    end
  end

  # Calling TTL has zero effect on the global stats, so we simply increment the
  # action's statistics.
  defp process_action(:ttl, { status, _value }) do
    [ { :ttl, status, 1 } ] ++ if status == :ok do
      [ { :global , :hitCount, 1 } ]
    else
      [ { :global , :missCount, 1 } ]
    end
  end

  # An update will increment the update stats, and if it was successful we also
  # register it in the global namespace as well.
  defp process_action(:update, { _status, value }) do
    [ { :update, value, 1 } ] ++ if value do
      [ { :global , :updateCount, 1 } ]
    else
      []
    end
  end

  # Both the get_and_update and increment calls do either an update or a set depending on whether
  # the key existed in the cache before the operation.
  defp process_action(action, { status, _value }) when action in [ :get_and_update, :decr, :incr ] do
    [ { action, status, 1 }, { :global, status == :ok && :updateCount || :setCount, 1 } ]
  end

  # Any TTL based changes just carry out updates inside the cache, so we increment the update count
  # in the global namespace.
  defp process_action(action, { _status, value }) when action in [ :expire, :expire_at, :persist, :refresh ] do
    [ { action, value, 1 } ] ++ if value do
      [ { :global , :updateCount, 1 } ]
    else
      []
    end
  end

  # Catch all stats should simply increment the call count by 1.
  defp process_action(action, _result) do
    [ { action, :calls, 1 } ]
  end

  # Increments a given set of statistics by a given amount. If the amount is not
  # provided, we default to a value of 1. We accept a list of fields to work with
  # as it's not unusual for an action to increment various fields at the same time.
  defp increment({ action, fields, amount }, stats) do
    increment(stats, action, List.wrap(fields), amount)
  end
  defp increment(stats, action, fields, amount \\ 1) do
    { _, updated_stats } = Map.get_and_update(stats, action, fn(inner_stats) ->
      action_stats =
        fields
        |> List.wrap
        |> Enum.reduce(inner_stats || %{ }, &(Util.increment_map_key(&2, &1, amount)))

      { nil, action_stats }
    end)
    updated_stats
  end

  # Converts the result of a request into the type of count it should increment
  # in the global statistics namespace.
  defp normalize_status(:ok), do: [ :hitCount ]
  defp normalize_status(:missing), do: [ :missCount ]
  defp normalize_status(:loaded), do: [ :missCount, :loadCount ]

end
