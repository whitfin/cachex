defmodule Cachex.Actions.Prune do
  @moduledoc false
  # Command module to allow pruning a cache to a maximum size.
  #
  # This command will trigger an LRW-style pruning of a cache based on
  # the provided maximum value. Various controls are provided on how to
  # exactly prune the table.
  #
  # This command is used by the various limit hooks provided by Cachex.
  alias Cachex.Query
  alias Cachex.Services.Informant

  # add required imports
  import Cachex.Spec

  # compile our match to avoid recalculating
  @query Query.build(output: {:key, :modified})

  ##############
  # Public API #
  ##############

  @doc """
  Prunes cache keyspsace to the provided amount.

  This function will enforce cache bounds using a least recently written (LRW)
  eviction policy. It will trigger a Janitor purge to clear expired records
  before attempting to trim older cache entries.
  """
  def execute(cache() = cache, size, options) do
    buffer =
      case Keyword.get(options, :buffer, 100) do
        val when val < 0 -> 100
        val -> val
      end

    reclaim = Keyword.get(options, :reclaim, 0.1)
    reclaim_bound = round(size * reclaim)

    case Cachex.size(cache, const(:local) ++ const(:notify_false)) do
      cache_size when cache_size <= size ->
        notify_worker(0, cache)

      cache_size ->
        cache_size
        |> calculate_reclaim(size, reclaim_bound)
        |> calculate_poffset(cache)
        |> erase_lower_bound(cache, buffer)
        |> notify_worker(cache)
    end

    true
  end

  ###############
  # Private API #
  ###############

  # Calculates the space to reclaim inside a cache.
  #
  # This is a function of the maximum cache size, the reclaim bound and the
  # current size of the cache. A positive result from this function means that
  # we need to carry out evictions, whereas a negative results means that the
  # cache is currently underpopulated.
  defp calculate_reclaim(current_size, size, reclaim_bound),
    do: (size - reclaim_bound - current_size) * -1

  # Calculates the purge offset of a cache.
  #
  # Basically this means that if the cache is overpopulated, we would trigger
  # a Janitor purge to see if expirations bring the cache back under the max
  # size limits. The resulting amount of removed records is then offset against
  # the reclaim space, meaning that a positive result require us to carry out
  # further evictions manually down the chain.
  defp calculate_poffset(reclaim_space, cache) when reclaim_space > 0,
    do: reclaim_space - Cachex.purge(cache, const(:local))

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
  defp erase_lower_bound(offset, cache(name: name) = cache, buffer) when offset > 0 do
    options =
      :local
      |> const()
      |> Enum.concat(const(:notify_false))
      |> Enum.concat(buffer: buffer)

    cache
    |> Cachex.stream(@query, options)
    |> Enum.sort(fn {_k1, t1}, {_k2, t2} -> t1 < t2 end)
    |> Enum.take(offset)
    |> Enum.each(fn {k, _t} -> :ets.delete(name, k) end)

    offset
  end

  defp erase_lower_bound(offset, _state, _buffer),
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
    do: Informant.broadcast(state, {:clear, [[]]}, offset)

  defp notify_worker(_offset, _state),
    do: :ok
end
