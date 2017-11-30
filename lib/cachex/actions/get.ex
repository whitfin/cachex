defmodule Cachex.Actions.Get do
  @moduledoc false
  # This module provides the implementation for the Get action, which is in charge
  # of retrieving values from the cache by key. If the record has expired, it is
  # purged on read. If the record is missing, we allow the use of fallback functions
  # to populate a new value in the cache.

  # we need our imports
  import Cachex.Actions
  import Cachex.Spec

  # add some aliases
  alias Cachex.Actions

  @doc """
  Retrieves a value from inside the cache.

  This action supports the use of default fallbacks set on a cache state for the
  ability to fallback to another cache, or to compute any missing values. If the
  value does not exist in the cache, fallbacks can be used to set the value in
  the cache for next time. Note that `nil` values inside the cache are treated
  as missing values.
  """
  defaction get(cache() = cache, key, options) do
    case Actions.read(cache, key) do
      entry(value: value) ->
        { :ok, value }
      _missing ->
        { :missing, nil }
    end
  end
end
