defmodule Cachex.Actions.Ttl do
  @moduledoc false
  # This module controls TTL retrieval for cache records by calculating the offset
  # between the touch and ttl fields inside a record. The implementation also
  # accounts for expirations in order to ensure consistency in results provided
  # to the developer.

  # we need our imports
  import Cachex.Actions
  import Cachex.Spec

  # add some aliases
  alias Cachex.Actions

  @doc """
  Retrieves the remaining TTL for a cache item.

  If the cache item has no TTL, a nil value is returned. If the item is missing,
  a nil is returned, tagged with a :missing flag. Otherwise a Tuple of :ok and
  the remaining time to list (in milliseconds) is returned.

  There are currently no recognised options, the argument only exists for future
  proofing.
  """
  defaction ttl(cache() = cache, key, options) do
    cache
    |> Actions.read(key)
    |> handle_record
  end

  # Handles the record coming back from the read. We normalize the TTL value at
  # this point. If there is no TTL, we return a nil value. Otherwise we calculate
  # the time remaining and return that to the user. If the record does not exist,
  # we just return a missing result.
  defp handle_record(entry(ttl: nil)),
    do: { :ok, nil }
  defp handle_record(entry(touched: touched, ttl: ttl)),
    do: { :ok, touched + ttl - now() }
  defp handle_record(_missing),
    do: { :missing, nil }
end
