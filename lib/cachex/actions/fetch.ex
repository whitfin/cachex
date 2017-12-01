defmodule Cachex.Actions.Fetch do
  @moduledoc """
  Command module to enable fetching on cache misses.

  This is a replacement for the `get()` command in Cachex v2 which would accept
  a `:fallback` option to fetch on cache miss. It operates in the same way, except
  that the function to use when fetching is an explicit argument.

  If the fetch function is not provided, the `fetch()` command will try to lookup
  a default fetch function from the cache state and use that instead. If neither
  exist, an error will be returned.
  """
  alias Cachex.Actions.Get
  alias Cachex.Actions.Set
  alias Cachex.Util

  # provide needed macros
  import Cachex.Actions
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Retrieves an entry from a cache, falling back to fetch fetching on a miss.

  The fallback argument can be treated as optional if a default fetch function is
  attached to the global cache at startup, in which case it will be executed instead.

  The fallback function is only executed if the key being retrieved does not exist
  in the cache; otherwise it is immediately returned. Any fetched values will be
  placed in the cache in order to allow read-through caches.
  """
  defaction fetch(cache() = cache, key, fallback, options) do
    with { :missing, nil } <- Get.execute(cache, key, const(:notify_false)) do
      cache
      |> handle_fallback(fallback, key)
      |> Util.normalize_commit
      |> handle_commit(cache, key)
    end
  end

  ###############
  # Private API #
  ###############

  # Executes a fallback based on the arity of the fallback function.
  #
  # If only a single argument is expected, the key alone is passed through. For
  # any other arity, we pass through the key and the default state (which can
  # be nil). This will therefore crash if the provided arity is invalid.
  defp handle_fallback(_cache, fallback, key) when is_function(fallback, 1),
    do: fallback.(key)
  defp handle_fallback(cache(fallback: fallback(provide: provide)), fallback, key),
    do: fallback.(key, provide)

  # Handles the result of a fallback execution.
  #
  # If the returned Tuple is tagged with the `:commit` flag, the value is
  # persisted to the cache table. If no, the result is returned as it without
  # being stored inside the cache.
  defp handle_commit(result, cache, key) do
    with { :commit, val } <- result do
      Set.execute(cache, key, val, const(:notify_false))
    end
    result
  end
end
