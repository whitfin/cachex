defmodule Cachex.Actions.Stats do
  @moduledoc false
  # This module controls the retrieval of any stats associated with a cache. We
  # have to first locate the Stats hook inside the state. If there isn't one, we
  # return an error. If there is, we normalize according to provided options and
  # return them to the user.

  # we need constants
  import Cachex.Errors
  import Cachex.Spec

  # add some aliases
  alias Cachex.Cache
  alias Cachex.Hook

  @doc """
  Retrieves statistics for a cache.

  If the cache does not have statistics on, an error is returned. Otherwise a
  Map containing various statistics is returned to the user in an ok Tuple.

  Everything in here is out of bound of the main process, so no Transaction have
  to taken into account, etc.
  """
  @spec execute(Cache.t, Keyword.t) :: { :ok, %{ } } | { :error, :stats_disabled }
  def execute(%Cache{ hooks: hooks(post: post_hooks) }, options) do
    post_hooks
    |> Enum.find(&find_hook/1)
    |> handle_hook(options)
  end

  # Locates a Hook for the Stats module, using function heads as the filter. If
  # the function head matches, we return true, otherwise we just return false.
  defp find_hook(hook(module: Cachex.Hook.Stats)),
    do: true
  defp find_hook(_hook),
    do: false

  # Uses a stats hook to retrieve pieces of the statistics container from the
  # running stats hook. If no hook is provided, we return an error because the
  # Stats hook is not running, meaning that stats are disabled.
  defp handle_hook(nil, _options),
    do: error(:stats_disabled)
  defp handle_hook(hook(ref: ref), options) do
    stats = Hook.Stats.retrieve(ref)

    final =
      options
      |> Keyword.get(:for, [:overview])
      |> List.wrap
      |> normalize(stats)
      |> Enum.sort
      |> Enum.into(%{})

    { :ok, final }
  end

  # This function normalizes the stats returned from the stats hook according to
  # what the developer wishes to retrieve stats for. In the case they have asked
  # for raw stats, we just return the raw payload coming back. If they're asked
  # for an overview, we do some enriching of the global stats to provide some
  # high level statistics (which are sufficient in most cases). If they've asked
  # for specific types of stats, we just pull all the keys out of the top level
  # and use the result (meaning that it could be empty if there are no stats of
  # the type the user is asking for).
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

  # This function generates a request rates Map, which is a map containing hit
  # and miss rates, as well as counts of hits and misses. This has to be defined
  # as separate functions in order to handle potential division by 0. All rates
  # will always be floats to ensure consistency (even when they are whole numbers).
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
