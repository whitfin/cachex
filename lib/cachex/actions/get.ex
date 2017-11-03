defmodule Cachex.Actions.Get do
  @moduledoc false
  # This module provides the implementation for the Get action, which is in charge
  # of retrieving values from the cache by key. If the record has expired, it is
  # purged on read. If the record is missing, we allow the use of fallback functions
  # to populate a new value in the cache.

  # we need our imports
  use Cachex.Actions

  # add some aliases
  alias Cachex.Actions
  alias Cachex.Actions.Fetch
  alias Cachex.State
  alias Cachex.Util

  @doc """
  Retrieves a value from inside the cache.

  This action supports the use of default fallbacks set on a cache state for the
  ability to fallback to another cache, or to compute any missing values. If the
  value does not exist in the cache, fallbacks can be used to set the value in
  the cache for next time. Note that `nil` values inside the cache are treated
  as missing values.

  Support for the use of the default fallback can be disabled by providing the
  `:fallback` option set to false. Naturally, this is enabled by default.
  """
  defaction get(%State{ } = state, key, options) do
    options
    |> Util.get_opt(:fallback, &is_boolean/1, true)
    |> handle_retrieval(state, key, options)
  end

  # Handles the retrieval of a value from the cache. This definition is used in the
  # case a default fallback is missing or has been explicitly disabled. We go straight
  # to the raw Actions interface to pull back a record and normalize it into a friendly
  # syntax for the user to handle. Expiration is taken into account behind the scenes.
  defp handle_retrieval(false, state, key, _options) do
    case Actions.read(state, key) do
      { ^key, _touched, _ttl, value } ->
        { :ok, value }
      _missing ->
        { :missing, nil }
    end
  end

  # Handles the retrieval of a value from the cache. This definition is in the case we
  # have a default (and enabled) fallback as that turns this operation into a fetch call,
  # so we just forward the arguments and the fallback through to the fetch/4 definition.
  defp handle_retrieval(true, state, key, options) do
    case state.fallback.action do
      nil -> handle_retrieval(false, state, key, options)
      fun -> Fetch.execute(state, key, fun, options)
    end
  end
end
