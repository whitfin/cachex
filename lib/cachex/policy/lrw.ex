defmodule Cachex.Policy.LRW do
  @moduledoc """
  Least recently written eviction policies for Cachex.

  This module provides general utilities for implementing an eviction policy for
  Cachex which will evict the least-recently written entries from the cache. This
  is determined by the touched time inside each cache record, which means that we
  don't have to store any additional tables to keep track of access time.

  There are several policies implemented using this algorithm:

  * `Cachex.Policy.LRW.Evented`

  Although the functions in this module are public, the way they function internally
  should be treated as private and subject to change at any point.
  """
  use Cachex.Hook
  use Cachex.Policy

  # import macros
  import Cachex.Spec

  # add internal aliases
  alias Cachex.Query
  alias Cachex.Services.Informant

  # compile our QLC match at runtime to avoid recalculating
  @qlc_match Query.raw(true, {:key, :touched})

  ####################
  # Policy Behaviour #
  ####################

  @doc false
  # Backwards compatibility with < v3.5.x defaults
  defdelegate hooks(limit), to: __MODULE__.Evented

  #############
  # Algorithm #
  #############

  @doc """
  Enforces cache bounds based on the provided limit.

  This function will enforce cache bounds using a least recently written (LRW)
  eviction policy. It will trigger a Janitor purge to clear expired records
  before attempting to trim older cache entries.

  The `:batch_size` option can be set in the limit options to dictate how many
  entries should be removed at once by this policy. This will default to a batch
  size of 100 entries at a time.
  """
  def enforce_bounds(cache, limit() = limit) do
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
  # used to determine the sort order required for LRW. We transform this sort using
  # a QLC cursor and pass it through to `erase_cursor/3` to delete.
  defp erase_lower_bound(offset, cache(name: name), batch_size)
       when offset > 0 do
    name
    |> :ets.table(traverse: {:select, @qlc_match})
    |> :qlc.sort(order: fn {_k1, t1}, {_k2, t2} -> t1 < t2 end)
    |> :qlc.cursor()
    |> erase_cursor(name, offset, batch_size)

    offset
  end

  defp erase_lower_bound(offset, _state, _batch_size),
    do: offset

  # Erases entries in an LRW ETS cursor.
  #
  # This will exhaust a QLC cursor by taking in a provided cursor and removing the first
  # N elements (where N is the number of entries we need to remove). Removals are done
  # in configurable batches according to the `:batch_size` option.
  #
  # This is a recursive function as we have to keep track of the number to remove,
  # as the removal is done by calling `erase_batch/3`. At the end of the recursion,
  # we make sure to delete the trailing QLC cursor to avoid it lying around still.
  defp erase_cursor(cursor, table, remainder, batch_size)
       when remainder > batch_size do
    erase_batch(cursor, table, batch_size)
    erase_cursor(cursor, table, remainder - batch_size, batch_size)
  end

  defp erase_cursor(cursor, table, remainder, _batch_size) do
    erase_batch(cursor, table, remainder)
    :qlc.delete_cursor(cursor)
  end

  # Erases a batch of entries from a QLC cursor.
  #
  # This is not the most performant way to do this (as far as I know), as
  # we need to pull a batch of entries from the table and then just pass
  # them back through to ETS to erase them by key. This is nowhere near as
  # performant as `:ets.select_delete/2` but appears to be required because
  # of the need to sort the QLC cursor by the touch time.
  defp erase_batch(cursor, table, batch_size) do
    for {key, _touched} <- :qlc.next_answers(cursor, batch_size) do
      :ets.delete(table, key)
    end
  end

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
    do: {:ok, 0}
end
