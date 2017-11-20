defmodule Cachex.Actions.Fetch do
  @moduledoc false
  # This module provides the implementation for the Fetch action, which is in charge
  # of retrieving values from the cache by key. If the record has expired, it is
  # purged on read. If the record is missing, we use fallback functions to populate
  # a new value in the cache.

  # we need our imports
  use Cachex.Include,
    actions: true,
    constants: true

  # add some aliases
  alias Cachex.Actions.Get
  alias Cachex.Actions.Set
  alias Cachex.Cache
  alias Cachex.Util

  @doc """
  Retrieves a value from inside the cache, falling back to the provided function
  if the value is missing.

  The third argument can be used to provide a function which will generate a value
  based on the key in the case the key is missing. This value will then be placed
  into the cache going forward in order to act as a read-through cache.
  """
  defaction fetch(%Cache{ } = cache, key, fallback, options) do
    with { :missing, nil } <- Get.execute(cache, key, @notify_false) do
      cache
      |> handle_fallback(fallback, key)
      |> Util.normalize_commit
      |> handle_commit(cache, key)
    end
  end

  # Executes a fallback based on the cache and fallback state. If the provided
  # fallback only accepts a single argument, we pass through the key. For any
  # other arity we pass through the key and the state of the fallback (which
  # can be set to nil). This enables easy definition whilst keeping structure.
  defp handle_fallback(_cache, fallback, key) when is_function(fallback, 1),
    do: fallback.(key)
  defp handle_fallback(%Cache{ fallback: %{ state: state } }, fallback, key),
    do: fallback.(key, state)

  # Handles the result of a fallback commit. If it's tagged with the :commit flag,
  # the value is persisted through to the backing table, otherwise the result is
  # returned as-is (i.e. no persistence and without any extra modifications).
  defp handle_commit(result, cache, key) do
    with { :commit, val } <- result do
      Set.execute(cache, key, val, @notify_false)
    end
    result
  end
end
