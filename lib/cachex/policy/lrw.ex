defmodule Cachex.Policy.LRW do
  @moduledoc """
  Least recently written eviction policies for Cachex.

  This module provides general utilities for implementing an eviction policy for
  Cachex which will evict the least-recently written entries from the cache. This
  is determined by the touched time inside each cache record, which means that we
  don't have to store any additional tables to keep track of access time.

  There are several options recognised by this policy which can be passed inside the
  limit structure when configuring your cache at startup:

    * `:batch_size`

      The batch size to use when paginating the cache to evict records. This defaults
      to 100, which is typically going to be fine for most cases, but this option is
      exposed in case there is need to customize it.

    * `:frequency`

      When this policy operates in scheduled mode, this option controls the frequency
      with which bounds will be checked. This is specified in milliseconds, and will
      default to once per second (1000). Feel free to tune this based on how strictly
      you wish to enforce your cache limits.

    * `:immediate`

      Sets this policy to enforce bounds reactively. If this option is set to `true`,
      bounds will be checked immediately when a write is made to the cache rather than
      on a timed schedule. This has the result of being much more accurate with the
      size of a cache, but has higher overhead due to listening on cache writes.

      Setting this to `true` will disable the scheduled checks and thus the `:frequency`
      option is ignored in this case.

  While the overall behaviour of this policy should always result in the same outcome,
  the way it operates internally may change. As such, the internals of this module
  should not be relied upon and should not be considered part of the public API.
  """
  use Cachex.Policy

  # import macros
  import Cachex.Spec

  # add internal aliases
  alias Cachex.Query
  alias Cachex.Services.Informant

  # compile our match to avoid recalculating
  @ets_match Query.raw(true, {:key, :touched})

  ####################
  # Policy Behaviour #
  ####################

  @doc """
  Configures hooks required to back this policy.
  """
  def hooks(limit(options: options) = limit),
    do: [
      hook(
        state: limit,
        module:
          case Keyword.get(options, :immediate) do
            true -> __MODULE__.Evented
            _not -> __MODULE__.Scheduled
          end
      )
    ]

  #############
  # Algorithm #
  #############

  @doc false
  # Enforces cache bounds based on the provided limit.
  #
  # This function will enforce cache bounds using a least recently written (LRW)
  # eviction policy. It will trigger a Janitor purge to clear expired records
  # before attempting to trim older cache entries.
  #
  # Please see module documentation for options available inside the limits.
  @spec apply_limit(Cachex.t(), Cachex.Spec.limit()) :: :ok
  def apply_limit(cache() = cache, limit() = limit) do
    limit(size: max_size, reclaim: reclaim, options: options) = limit

    batch_size =
      case Keyword.get(options, :batch_size, 100) do
        val when val < 0 -> 100
        val -> val
      end

    reclaim_bound = round(max_size * reclaim)

    case Cachex.size!(cache, const(:notify_false)) do
      cache_size when cache_size <= max_size ->
        notify_worker(0, cache)

      cache_size ->
        cache_size
        |> calculate_reclaim(max_size, reclaim_bound)
        |> calculate_poffset(cache)
        |> erase_lower_bound(cache, batch_size)
        |> notify_worker(cache)
    end
  end

  # Calculates the space to reclaim inside a cache.
  #
  # This is a function of the maximum cache size, the reclaim bound and the
  # current size of the cache. A positive result from this function means that
  # we need to carry out evictions, whereas a negative results means that the
  # cache is currently underpopulated.
  defp calculate_reclaim(current_size, max_size, reclaim_bound),
    do: (max_size - reclaim_bound - current_size) * -1

  # Calculates the purge offset of a cache.
  #
  # Basically this means that if the cache is overpopulated, we would trigger
  # a Janitor purge to see if expirations bring the cache back under the max
  # size limits. The resulting amount of removed records is then offset against
  # the reclaim space, meaning that a positive result require us to carry out
  # further evictions manually down the chain.
  defp calculate_poffset(reclaim_space, cache) when reclaim_space > 0,
    do: reclaim_space - Cachex.purge!(cache)

  # Erases the least recently written records up to the offset limit.
  #
  # If the provided offset is not positive we don't do anything as it signals that
  # the cache is already within the correctly sized limits so we just pass through
  # as a no-op.
  #
  # In the case the offset is positive, it represents the number of entries we need
  # to remove from the cache table. We do this by traversing the underlying ETS table,
  # which only selects the key and touch time as a minor optimization. The key is
  # naturally required when it comes to removing the document, and the touch time is
  # used to determine the sort order required for LRW.
  defp erase_lower_bound(offset, cache(name: name) = cache, batch)
       when offset > 0 do
    cache
    |> Cachex.stream!(@ets_match, const(:notify_false) ++ [batch_size: batch])
    |> Enum.sort(fn {_k1, t1}, {_k2, t2} -> t1 < t2 end)
    |> Enum.take(offset)
    |> Enum.each(fn {k, _t} -> :ets.delete(name, k) end)

    offset
  end

  defp erase_lower_bound(offset, _state, _batch),
    do: offset

  # Broadcasts the number of removed entries to the cache hooks.
  #
  # If the offset is not positive we didn't have to remove anything and so we
  # don't broadcast any results. An 0 Tuple is returned just to keep compatibility
  # with the response type from `Informant.broadcast/3`.
  #
  # It should be noted that we use a `:clear` action here as these evictions are
  # based on size and not on expiration. The evictions done during the purge earlier
  # in the pipeline are reported separately and we're only reporting the delta at this
  # point in time. Therefore remember that it's important that we're ignoring the
  # results of `clear()` and `purge()` calls in this hook, otherwise we would end
  # up in a recursive loop due to the hook system.
  defp notify_worker(offset, state) when offset > 0,
    do: Informant.broadcast(state, {:clear, [[]]}, {:ok, offset})

  defp notify_worker(_offset, _state),
    do: :ok
end
