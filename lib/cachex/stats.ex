defmodule Cachex.Stats do
  @moduledoc false
  # A simple statistics container, used to keep track of various operations on
  # a given cache. This is used as a post hook for a cache and provides an example
  # of what a hook can look like. This container has no knowledge of the cache
  # it belongs to, it only keeps track of an internal struct.

  # use the hooks
  use Cachex.Hook

  # add some aliases
  alias Cachex.Stats.Registry
  alias Cachex.Util

  @doc """
  Initializes a new stats container, setting the creation date to the current time.

  This state will be passed into each handler in this server.
  """
  def init(_options \\ []) do
    { :ok, add_meta(%{ }, :creationDate, Cachex.Util.now()) }
  end

  @doc """
  Forward any successful calls through to the stats container.

  We don't keep statistics on requests which errored, to avoid false positives
  about what exactly is going on inside a given cache.
  """
  def handle_notify({ action, _options }, { status, _val } = result, stats) when status != :error do
    action
    |> Registry.register(result, stats)
    |> Util.ok
  end

  @doc """
  Handles a call to retrieve the stats as they currently stand. We finalize the
  stats and return them to the calling process.
  """
  def handle_call({ :retrieve_stats, options }, stats) do
    normalized_options =
      options
      |> Keyword.get(:for, :global)
      |> List.wrap
      |> Enum.filter(&(&1 != :meta))

    finalized_stats = case normalized_options do
      [:raw] -> stats
      option -> finalize(stats, option)
    end

    { :ok, finalized_stats, stats }
  end

  @doc """
  Retrieves the stats for a given cache. This is simply shorthand for firing off
  a request to the stats hook. We provide it to make it more obvious to retrieve
  statistics.
  """
  @spec retrieve(stats_ref :: pid | atom, options :: Keyword.t) :: %{ }
  def retrieve(stats_ref, options \\ []) do
    GenEvent.call(stats_ref, __MODULE__, { :retrieve_stats, options })
  end

  # Adds a metadata key to the cache statistics. This is just a simple get/set
  # and doesn't provide increments because this contains things just as dates.
  defp add_meta(%{ :meta => meta } = stats, key, val) do
    Map.put(stats, :meta, Map.put(meta, key, val))
  end
  defp add_meta(%{ } = stats, key, val) do
    stats
    |> Map.put(:meta, %{ })
    |> add_meta(key, val)
  end

  # Plucks out the global component of the statistics if requested. This is just
  # to maintain backwards compatibility with the previous iterations.
  defp extract_global(stats, [ :global ]) do
    stats
    |> Map.delete(:global)
    |> Map.merge(stats.global || %{ })
  end
  defp extract_global(stats, _other), do: stats

  # Finalizes the stats to be returned in some form. Asking for different keys
  # provides you with various bonus statistics about those keys. If you don't
  # ask for anything specific, you get a high level overview about what's in the
  # cache.
  defp finalize(stats, options) when is_list(options) do
    options
    |> Enum.map(fn(option) ->
        case Map.get(stats, option) do
          nil -> Map.new([{ option, %{ } }])
          val -> Map.new([{ option, finalize(val, option) }])
        end
       end)
    |> Enum.reduce(%{}, &(Map.merge(&2, &1)))
    |> Map.merge(stats.meta)
    |> extract_global(options)
  end
  defp finalize(stats, :global) do
    hits_count = Map.get(stats, :hitCount, 0)
    miss_count = Map.get(stats, :missCount, 0) + Map.get(stats, :loadCount, 0)

    req_rates = case hits_count + miss_count do
      0 -> %{ }
      v ->
        cond do
          hits_count == 0 -> %{ requestCount: v, hitRate: 0, missRate: 100 }
          miss_count == 0 -> %{ requestCount: v, hitRate: 100, missRate: 0 }
          true -> %{
            requestCount: v,
            hitRate: hits_count / v,
            missRate: miss_count / v
          }
        end
    end

    stats
    |> Map.merge(req_rates)
    |> Enum.sort(&(elem(&1, 0) > elem(&2, 0)))
    |> Enum.into(%{})
  end
  defp finalize(stats, option) do
    Map.has_key?(stats, option) && stats[option] || stats
  end

end
