defmodule Cachex.Actions.Fetch do
  @moduledoc false
  # This module provides the implementation for the Fetch action, which is in charge
  # of retrieving values from the cache by key. If the record has expired, it is
  # purged on read. If the record is missing, we use fallback functions to populate
  # a new value in the cache.

  # we need our imports
  use Cachex.Actions

  # add some aliases
  alias Cachex.Actions.Get
  alias Cachex.Actions.Set
  alias Cachex.State
  alias Cachex.Util

  defaction fetch(%State{ } = state, key, fallback, options) do
    with { :missing, nil } <- Get.execute(state, key, @notify_false) do
      state
      |> handle_fallback(fallback, key)
      |> Util.normalize_commit
      |> handle_commit(state, key)
    end
  end

  defp handle_fallback(_state, fallback, key) when is_function(fallback, 1),
    do: fallback.(key)
  defp handle_fallback(%State{ fallback: %{ state: state } }, fallback, key),
    do: fallback.(key, state)

  defp handle_commit({ :ignore, _val } = result, _state, _key),
    do: result
  defp handle_commit({ :commit, val } = result, state, key) do
    Set.execute(state, key, val, @notify_false)
    result
  end
end
