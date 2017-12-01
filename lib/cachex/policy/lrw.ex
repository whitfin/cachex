defmodule Cachex.Policy.LRW do
  @moduledoc """
  Least recently written eviction policy for Cachex.

  This module provides an eviction policy for Cachex, evicting the least-recently
  written entries from the cache. This is determined by the touched time inside
  each cache record, which means that this eviction is almost zero cost, consuming
  no additional memory beyond that of the running GenServer.

  This policy accepts a reclaim space to determine how much of the cache to evict,
  allowing the user to determine exactly how much they'd like to trim in the event
  they've gone over the limit.

  The `:batch_size` option can be set in the limit options to dictate how many
  entries should be removed at once by this policy. This will default to a batch
  size of 100 entries at a time.

  This eviction is relatively fast, and should keep the cache below bounds at most
  times. Note that many writes in a very short amount of time can flood the cache,
  but it should recover given a few seconds.
  """
  use Cachex.Hook
  use Cachex.Policy

  # import macros
  import Cachex.Spec

  # add internal aliases
  alias Cachex.Services.Informant
  alias Cachex.Util

  # A list of actions which add items to the cache.
  #
  # We only need to operate on these actions, allowing us to optimize and
  # avoid checking cache bounds when there's no change of a change.
  #
  # This will become moot once we have the ability to subscribe to a subset
  # of actions from inside a hook definition (planned for the future).
  @additives MapSet.new([ :set, :update, :incr, :get_and_update, :decr ])

  # compile our QLC match at runtime to avoid recalculating
  @qlc_match Util.create_match([ { { :"$1", :"$2" } } ], [ ])

  ####################
  # Policy Behaviour #
  ####################

  @doc """
  Retrieves a list of hooks required to run against this policy.
  """
  @spec hooks(Spec.limit) :: [ Spec.hook ]
  def hooks(limit),
    do: [
      hook(
        args: limit,
        module: __MODULE__,
        provide: [ :cache ],
        type: :post
      )
    ]

  ##################
  # Initialization #
  ##################

  @doc false
  # Initializes this policy using the limit being enforced.
  #
  # The maximum size is stored in the state, alongside the pre-calculated
  # number to trim down to. The batch size to use when removing records is
  # also configurable via the provided options.
  def init(limit(size: max_size, reclaim: reclaim, options: options)) do
    trim_bound = round(max_size * reclaim)

    batch_size =
      case Keyword.get(options, :batch_size, 100) do
        val when val < 0 -> 100
        val -> val
      end

    { :ok, { max_size, trim_bound, batch_size, nil } }
  end

  #############
  # Listeners #
  #############

  @doc false
  # Handles notification of a cache action.
  #
  # This will check if the action can modify the size of the cache, and if so will
  # execute the boundary enforcement to trim the size as needed.
  #
  # Note that this will ignore error results and only operates on actions which are
  # able to cause a net gain in cache size (so removals are also ignored).
  def handle_notify({ action, _options }, { status, _value }, opts)
  when status != :error do
    if MapSet.member?(@additives, action) do
      enforce_bounds(opts)
    end
    { :ok, opts }
  end

  @doc false
  # Receives a provisioned cache instance.
  #
  # The provided cache is then stored in the cache and used for cache calls going
  # forwards, in order to skip the lookups inside the cache overseer for performance.
  def handle_provision({ :cache, cache }, { max_size, reclaim, batch, _cache }),
    do: { :ok, { max_size, reclaim, batch, cache } }

  #############
  # Algorithm #
  #############

  # Enforces the bounds of a cache based on the provided state.
  #
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
  defp enforce_bounds({ max_size, reclaim, batch, cache }) do
    case Cachex.size!(cache, const(:notify_false)) do
      cache_size when cache_size <= max_size ->
        notify_worker(0, cache)
      cache_size ->
        cache_size
        |> calculate_reclaim(max_size, reclaim)
        |> calculate_poffset(cache)
        |> erase_lower_bound(cache, batch)
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
  defp erase_lower_bound(offset, cache(name: name), batch_size) when offset > 0 do
    name
    |> :ets.table([ traverse: { :select, @qlc_match } ])
    |> :qlc.sort([ order: fn({ _k1, t1 }, { _k2, t2  }) -> t1 < t2 end ])
    |> :qlc.cursor
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
  defp erase_cursor(cursor, table, remainder, batch_size) when remainder > batch_size do
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
    for { key, _touched } <- :qlc.next_answers(cursor, batch_size) do
      :ets.delete(table, key)
    end
  end

  # Broadcasts the number of removed entries to the cache hooks.
  #
  # If the offset is not positive we didn't have to remove anything and so we
  # don't broadcast any results. An 0 Tuple is returned just to keep compability
  # with the response type from `Informant.broadcast/3`.
  #
  # It should be noted that we use a `:clear` action here as these evictions are
  # based on size and not on expiration. The evictions done during the purge earlier
  # in the pipeline are reported separately and we're only reporting the delta at this
  # point in time. Therefore remember that it's important that we're ignoring the
  # results of `clear()` and `purge()` calls in this hook, otherwise we would end
  # up in a recursive loop due to the hook system.
  defp notify_worker(offset, state) when offset > 0,
    do: Informant.broadcast(state, { :clear, [[]] }, { :ok, offset })
  defp notify_worker(_offset, _state),
    do: { :ok, 0 }
end
