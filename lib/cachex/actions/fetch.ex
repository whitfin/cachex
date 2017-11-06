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

  @doc """
  Retrieves a value from inside the cache, falling back to the provided function
  if the value is missing.

  The third argument can be used to provide a function which will generate a value
  based on the key in the case the key is missing. This value will then be placed
  into the cache going forward in order to act as a read-through cache.
  """
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

  # Executes a fallback based on the cache and fallback state. If the provided
  # fallback only accepts a single argument, we pass through the key. For any
  # other arity we pass through the key and the state of the fallback (which
  # can be set to nil). This enables easy definition whilst keeping structure.
  defp handle_fallback(_state, fallback, key) when is_function(fallback, 1),
    do: fallback.(key)
  defp handle_fallback(%State{ fallback: %{ state: state } }, fallback, key),
    do: fallback.(key, state)

  # Handles the result of a fallback commit. If it's tagged with the :commit flag,
  # the value is persisted through to the backing table, otherwise the result is
  # returned as-is (i.e. no persistence and without any extra modifications).
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

  # Returns true only if the option provided is set against the :notify
  # key, which is signalled in the first element of each tuple.
  defp is_notify_opt?({ :notify, _value }), do: true
  defp is_notify_opt?({ _option, _value }), do: false
end
