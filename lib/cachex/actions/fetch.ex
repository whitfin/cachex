defmodule Cachex.Actions.Fetch do
  @moduledoc false
  # Command module to enable fetching on cache misses.
  #
  # This is a replacement for the `get()` command in Cachex v2 which would accept
  # a `:fallback` option to fetch on cache miss. It operates in the same way, except
  # that the function to use when fetching is an explicit argument.
  #
  # If the fetch function is not provided, the `fetch()` command will try to lookup
  # a default fetch function from the cache state and use that instead. If neither
  # exist, an error will be returned.
  alias Cachex.Actions.Get
  alias Cachex.Services.Courier

  # provide needed macros
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
  def execute(cache() = cache, key, fallback, options) do
    with { :ok, nil } <- Get.execute(cache, key, []) do
      Courier.dispatch(cache, key, generate_task(cache, fallback, key), options)
    end
  end

  ###############
  # Private API #
  ###############

  # Generates a courier task based on the arity of the fallback function.
  #
  # If only a single argument is expected, the key alone is passed through. For
  # any other arity, we pass through the key and the default state (which can
  # be nil). This will therefore crash if the provided arity is invalid.
  defp generate_task(cache(fallback: fallback(state: state)), fallback, key) do
    case :erlang.fun_info(fallback)[:arity] do
      0 -> fn -> fallback.() end
      1 -> fn -> fallback.(key) end
      _ -> fn -> fallback.(key, state) end
    end
  end
end
