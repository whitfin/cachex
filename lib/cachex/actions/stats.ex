defmodule Cachex.Actions.Stats do
  @moduledoc false

  alias Cachex.Hook
  alias Cachex.State

  def execute(%State{ post_hooks: hooks }, options \\ []) when is_list(options) do
    hooks
    |> Enum.find(&find_hook/1)
    |> handle_hook(options)
  end

  defp find_hook(%Hook{ module: Cachex.Hook.Stats }) do
    true
  end
  defp find_hook(_hook) do
    false
  end

  defp handle_hook(nil, _options) do
    Cachex.Errors.stats_disabled()
  end
  defp handle_hook(%Hook{ ref: ref }, options) do
    stats = Cachex.Hook.Stats.retrieve(ref)

    final =
      options
      |> Keyword.get(:for, :overview)
      |> List.wrap
      |> normalize(stats)
      |> Enum.sort
      |> Enum.into(%{})

    { :ok, final }
  end

  defp normalize([ :raw ], stats) do
    stats
  end
  defp normalize([ :overview ], stats) do
    meta   = Map.get(stats,   :meta, %{ })
    global = Map.get(stats, :global, %{ })

    load_count = Map.get(global, :loadCount, 0)
    hits_count = Map.get(global,  :hitCount, 0)
    miss_count = Map.get(global, :missCount, 0) + load_count

    req_rates = case hits_count + miss_count do
      0 -> %{ }
      v -> generate_rates(v, hits_count, miss_count)
    end

    %{ }
    |> Map.merge(meta)
    |> Map.merge(global)
    |> Map.merge(req_rates)
  end
  defp normalize(keys, stats) do
    Enum.filter(stats, fn({ k, _v }) ->
      k in keys
    end)
  end

  defp generate_rates(reqs, 0, misses), do: %{
    requestCount: reqs,
    hitCount: 0,
    hitRate: 0.0,
    missCount: misses,
    missRate: 100.0
  }
  defp generate_rates(reqs, hits, 0), do: %{
    requestCount: reqs,
    hitCount: hits,
    hitRate: 100.0,
    missCount: 0,
    missRate: 0.0
  }
  defp generate_rates(reqs, hits, misses), do: %{
    requestCount: reqs,
    hitCount: hits,
    hitRate: (hits / reqs) * 100,
    missCount: misses,
    missRate: (misses / reqs) * 100
  }

end
