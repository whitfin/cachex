defmodule Cachex.Actions.Fetch do
  @moduledoc false
  # This module provides the implementation for the Fetch action, which is in charge
  # of retrieving values from the cache by key. If the record has expired, it is
  # purged on read. If the record is missing, we use fallback functions to populate
  # a new value in the cache.

  # we need our imports
  use Cachex.Actions

  # add some aliases
  alias Cachex.Actions
  alias Cachex.Actions.Set
  alias Cachex.State
  alias Cachex.Util

  defaction fetch(%State{ } = state, key, fallback, options) do
    case Actions.read(state, key) do
      { ^key, _touched, _ttl, value } ->
        { :ok, value }
      _missing ->
        state
        |> handle_fallback(fallback, key)
        |> Util.normalize_commit
        |> handle_commit(state, key, options)
    end
  end

  defp handle_fallback(_state, fallback, key) when is_function(fallback, 1),
    do: fallback.(key)
  defp handle_fallback(%State{ fallback: %{ state: state } }, fallback, key),
    do: fallback.(key, state)

  defp handle_commit({ :ignore, _val } = result, _state, _key, _options),
    do: result
  defp handle_commit({ :commit, val } = result, state, key, options) do
    opts =
      options
      |> Enum.find([], &is_notify_opt?/1)
      |> List.wrap

    Set.execute(state, key, val, opts)

    result
  end

  defp is_notify_opt?({ :notify, _value }), do: true
  defp is_notify_opt?({ _option, _value }), do: false
end
