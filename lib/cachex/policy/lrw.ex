defmodule Cachex.Policy.LRW do
  @moduledoc false
  # This module provides an eviction policy for Cachex, evicting the least-recently
  # written entries from the cache. This is determined by the touched time inside
  # each cache record, which means that this eviction is almost zero cost, consuming
  # no additional memory beyond that of the running GenServer.
  #
  # This policy accepts a reclaim space to determine how much of the cache to evict,
  # allowing the user to determine exactly how much they'd like to trim in the event
  # they've gone over the limit.
  #
  # This eviction is relatively fast, and should keep the cache below bounds at most
  # times. Note that many writes in a very short amount of time can flood the cache,
  # but it should recover given a few seconds.

  # use the hook system
  use Cachex.Hook

  # add internal aliases
  alias Cachex.Cache
  alias Cachex.Services
  alias Cachex.Util

  # alias any services
  alias Services.Informant

  # store a list of actions which add items to the cache, as we only need to then
  # operate on these actions - this allows us to optimize and avoid checking size
  # when there's no chance of a size change since the last check
  @additives MapSet.new([ :set, :update, :incr, :get_and_update, :decr ])

  # batch size to delete with
  @del_count 50

  # compile our QLC match at runtime to avoid recalculating
  @qlc_match Util.create_match([ { { :"$1", :"$2" } } ], [ ])

  @doc """
  Initializes the policy, accepting a maximum size and a bound to trim by.

  We store a state of the maximum size, and a calculated number to trim to.
  """
  def init({ max_size, trim_bound }),
    do: { :ok, { max_size, round(max_size * trim_bound), nil } }

  @doc """
  Checks and enforces the bounds of the cache as needed.

  This notification will receive all actions taken by the cache, and uses them to
  determine when to trim the cache. We only operate on results which have not had
  an error, and whose actions are listed in the additives constant (as only actions)
  fitting this criteria can have a net gain in cache size.
  """
  def handle_notify({ action, _options }, { status, _value }, opts) when status != :error do
    if MapSet.member?(@additives, action) do
      enforce_bounds(opts)
    end
    { :ok, opts }
  end

  @doc """
  Retrieves a provisioned worker from the cache and stores it inside the state.

  This worker is then used going forward for any cache calls to avoid the overhead
  of looking up the state. Again an optimization.
  """
  def handle_info({ :provision, { :cache, cache } }, { max_size, trim_bound, _cache }),
    do: { :noreply, { max_size, trim_bound, cache } }

  # Suggest stepping through this pipeline a function at a time and reading the
  # associated comments. This pipeline controls the trimming of the cache to fit
  # the appropriate size.
  #
  # We start with the current size of the cache and pass it through to a function
  # which will calculate the a number of slots to reclaim in the cache. If the
  # number is positive, we carry out a Janitor purge and see if that brings us
  # back under the maximum size. If so, we're done and stop. If not, we then trim
  # the cache using a QLC cursor through the cache, deleting entries in batches.
  # Note that these deletions are sorted by the touch time to ensure we delete
  # the oldest first.
  #
  # Upon completion, we notify the worker itself to broadcast a message to all
  # hooks to ensure that hooks are notified of the evictions. This is only done
  # in the case that something has actually been removed, in order to avoid edge
  # cases and potentially breaking existing hook implementations.
  #
  # It's safe to always run through the pipeline here, but we check the cache
  # size as an optimization to speed up message processing when no evictions need
  # to happen. This is a slight speed boost, but it's noticeable - tests will fail
  # intermittently if this is not checked in this way.
  defp enforce_bounds({ max_size, reclaim_bound, cache }) do
    case Cachex.size!(cache, [ notify: false ]) do
      cache_size when cache_size <= max_size ->
        notify_worker(0, cache)
      cache_size ->
        cache_size
        |> calculate_reclaim(max_size, reclaim_bound)
        |> calculate_poffset(cache)
        |> erase_lower_bound(cache)
        |> notify_worker(cache)
    end
  end

  # Calculates the space to reclaim inside the cache, based on the maximum cache
  # size, the reclaim bound, and the current size of the cache. A positive result
  # from this function means we need to carry out evictions, whereas a negative
  # means that the cache is currently underpopulated.
  defp calculate_reclaim(current_size, max_size, reclaim_bound),
    do: (max_size - reclaim_bound - current_size) * -1

  # Calculates the purge offset of the cache. Basically this means that if the
  # cache is overpopulated, we would trigger a Janitor purge to see if it brings
  # us back under the cache limit. The resulting amount to remove is then returned.
  # Again, a positive result means that we still have evictions to carry out.
  defp calculate_poffset(reclaim_space, cache) when reclaim_space > 0,
    do: reclaim_space - Cachex.purge!(cache)

  # This is the cuts of the cache trimming. If the provided offset is negative,
  # it means that the cache is within the maximum size and so we just pass through
  # as a no-op.
  #
  # In the case that it's positive, it represents the number of items to remove
  # from the cache. We do this by using a traversal of the underlying ETS table,
  # which only selects the key and touch time. The key is obviously required when
  # it comes to removing the document, and the touch time is used to determine
  # the sorted order required for implementing LRW. We transform this sort using
  # a QLC cursor and pass it through to `erase_cursor/3` to delete.
  defp erase_lower_bound(offset, %Cache{ name: name }) when offset > 0 do
    name
    |> :ets.table([ traverse: { :select, @qlc_match } ])
    |> :qlc.sort([ order: fn({ _k1, t1 }, { _k2, t2  }) -> t1 < t2 end ])
    |> :qlc.cursor
    |> erase_cursor(name, offset)

    offset
  end
  defp erase_lower_bound(offset, _state),
    do: offset

  # This function erases a QLC cursor by taking in a provided cursor and removing
  # the first N elements from the cursor. Removals are done in batches according
  # to the compiled constant @del_count.
  #
  # This is a recursive function as we have to keep track of the number to remove,
  # as the removal is done by calling `erase_batch/3`. At the end of the recursion,
  # we make sure to remove the trailing QLC cursor to avoid leaving it around.
  defp erase_cursor(cursor, table, remaining) when remaining > @del_count do
    erase_batch(cursor, table, @del_count)
    erase_cursor(cursor, table, remaining - @del_count)
  end
  defp erase_cursor(cursor, table, remaining) do
    erase_batch(cursor, table, remaining)
    :qlc.delete_cursor(cursor)
  end

  # Erases a batch of entries from the table. We pull the next batch of entries
  # from the table and erase them by key. This is not as efficient as using the
  # `:ets.select_delete/2` function but is required due to the cursored sort.
  defp erase_batch(cursor, table, amount) do
    for { key, _touched } <- :qlc.next_answers(cursor, amount) do
      :ets.delete(table, key)
    end
  end

  # At the end of the pipeline we broadcast the eviction count to any listening
  # hooks. Remember that it's important that we're ignoring `clear/1` calls in
  # this hook, as otherwise we'd execute a check immediately after (on our report).
  # If the offset is not positive, we don't broadcast - meaning that we didn't
  # have to remove anything from the cache (the no-op from the above definitions).
  # It returns a tuple simply to keep compatibility with the return type coming
  # from `Worker.broadcast/3`.
  #
  # It should be noted that we use a `:clear` action here as these evictions are
  # based on size and not on TTL. The evictions done during the purge earlier in
  # the pipeline are reported separately and we're only reporting the delta at this
  # point in time.
  defp notify_worker(offset, state) when offset > 0,
    do: Informant.broadcast(state, { :clear, [[]] }, { :ok, offset })
  defp notify_worker(_offset, _state),
    do: { :ok, 0 }
end
