defmodule Cachex.Actions.Stats do
  @moduledoc false
  # Command module to allow cache statistics retrieval.
  #
  # This module is only active if the statistics hook has been enabled in
  # the cache, either via the stats option at startup or by providing the
  # hook manually.
  import Cachex.Errors
  import Cachex.Spec

  @doc """
  Retrieves statistics for a cache.

  This will return an error if statistics tracking has not been enabled,
  either via the options at cache startup, or manually by providing the hook.

  If the provided cache does not have statistics enabled, an error will be returned.
  """
  @spec execute(Spec.cache, Keyword.t) :: { :ok, %{ } } | { :error, :stats_disabled }
  def execute(cache(hooks: hooks(post: post_hooks)), options) do
    post_hooks
    |> Enum.find(&find_stats_hooks/1)
    |> handle_hook(options)
  end

  # Returns true if the provided value is a statistics hook.
  defp find_stats_hooks(hook(module: Cachex.Stats)),
    do: true
  defp find_stats_hooks(_hook),
    do: false

  # Retrieves statistics from the provided statistics hook.
  #
  # The statistics hook has built in support for retrieval, so we
  # just make a call over to the hook to retrieve the data.
  #
  # If the provided hook is missing, an error will be returned.
  defp handle_hook(nil, _options),
    do: error(:stats_disabled)
  defp handle_hook(hook(ref: ref), options) do
    stats = GenServer.call(ref, :retrieve)

    final =
      options
      |> Keyword.get(:for, [:overview])
      |> List.wrap
      |> normalize(stats)
      |> Enum.sort
      |> Enum.into(%{})

    { :ok, final }
  end

  # Normalizes the stats returned from the statistics hook.
  #
  # This uses the `:for` option to determine how to format the statistics. If
  # the `:raw` option has been provided, we just return the raw payload coming
  # back directly from the statistics server. If the `:for` option has specified
  # an overview, we do some enriching of the global stats to provide some high
  # level statistics.
  defp normalize([ :raw ], stats),
    do: stats
  defp normalize([ :overview ], stats) do
    meta   = Map.get(stats,   :meta, %{ })
    global = Map.get(stats, :global, %{ })

    hits_count = Map.get(global,  :hitCount, 0)
    miss_count = Map.get(global, :missCount, 0)

    req_rates = case hits_count + miss_count do
      0 -> %{ }
      v -> generate_rates(v, hits_count, miss_count)
    end

    %{ }
    |> Map.merge(meta)
    |> Map.merge(global)
    |> Map.merge(req_rates)
  end
  defp normalize(keys, stats),
    do: Map.take(stats, keys)

  # Generates request rates for statistics map.
  #
  # This will generate hit/miss rates as floats, even when they're integer
  # values to ensure consistency. This is separated out to easily handle the
  # potential to divide values by 0, avoiding a crash in the application.
  defp generate_rates(_reqs, 0, misses),
    do: %{
      hitCount: 0,
      hitRate: 0.0,
      missCount: misses,
      missRate: 100.0
    }
  defp generate_rates(_reqs, hits, 0),
    do: %{
      hitCount: hits,
      hitRate: 100.0,
      missCount: 0,
      missRate: 0.0
    }
  defp generate_rates(reqs, hits, misses),
    do: %{
      hitCount: hits,
      hitRate: (hits / reqs) * 100,
      missCount: misses,
      missRate: (misses / reqs) * 100
    }
end
