defmodule Cachex.Actions.Stats do
  @moduledoc false
  # Command module to allow cache statistics retrieval.
  #
  # This module is only active if the statistics hook has been enabled in
  # the cache, either via the stats option at startup or by providing the
  # hook manually.
  alias Cachex.Stats
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Retrieves statistics for a cache.

  This will return an error if statistics tracking has not been enabled,
  either via the options at cache startup, or manually by providing the hook.

  If the provided cache does not have statistics enabled, an error will be returned.
  """
  @spec execute(Cachex.Spec.cache(), Keyword.t()) ::
          {:ok, %{}} | {:error, :stats_disabled}
  def execute(cache() = cache, _options) do
    with {:ok, stats} <- Stats.retrieve(cache) do
      hits_count = Map.get(stats, :hits, 0)
      miss_count = Map.get(stats, :misses, 0)

      case hits_count + miss_count do
        0 ->
          {:ok, stats}

        v ->
          v
          |> generate_rates(hits_count, miss_count)
          |> Map.merge(stats)
          |> wrap(:ok)
      end
    end
  end

  ###############
  # Private API #
  ###############

  # Generates request rates for statistics map.
  #
  # This will generate hit/miss rates as floats, even when they're integer
  # values to ensure consistency. This is separated out to easily handle the
  # potential to divide values by 0, avoiding a crash in the application.
  defp generate_rates(_reqs, 0, misses),
    do: %{
      hits: 0,
      misses: misses,
      hit_rate: 0.0,
      miss_rate: 100.0
    }

  defp generate_rates(_reqs, hits, 0),
    do: %{
      hits: hits,
      misses: 0,
      hit_rate: 100.0,
      miss_rate: 0.0
    }

  defp generate_rates(reqs, hits, misses),
    do: %{
      hits: hits,
      misses: misses,
      hit_rate: hits / reqs * 100,
      miss_rate: misses / reqs * 100
    }
end
