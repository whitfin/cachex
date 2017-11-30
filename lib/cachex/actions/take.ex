defmodule Cachex.Actions.Take do
  @moduledoc false
  # Command module to allow taking of cache entries.
  #
  # The notion of taking a key is the act of retrieving a key and deleting it
  # in a single atomic action. It's useful when used to guarantee that a given
  # process retrieves the final value of an entry.
  #
  # Taking a key is clearly destructive, so it operates in a lock context.
  alias Cachex.Services.Informant
  alias Cachex.Services.Locksmith
  alias Cachex.Util

  # we need our imports
  import Cachex.Actions
  import Cachex.Spec

  @doc """
  Takes an entry from a cache.

  This will always remove the entry from the cache, ensuring that the entry no
  longer exists immediately after this call finishes.

  Expirations are lazily checked here, ensuring that even if a value is taken
  from the cache it's only returned if it has not yet expired.

  Taking a value happens in a lock aware context to ensure that the key isn't
  being currently locked by another write sequence.
  """
  defaction take(cache(name: name) = cache, key, options) do
    Locksmith.write(cache, key, fn ->
      name
      |> :ets.take(key)
      |> handle_take(cache)
    end)
  end

  # Handles the result of taking a key from the backing table.
  #
  # If an entry comes back from the call, we check for expiration before returning
  # back to the caller. If the entry has expired, we broadcast the expiry (as the
  # entry was already removed when we took if from the cache).
  defp handle_take([ entry(touched: touched, ttl: ttl, value: value) ], cache) do
    case Util.has_expired?(cache, touched, ttl) do
      false ->
        { :ok, value }
      true ->
        Informant.broadcast(
          cache,
          const(:purge_override_call),
          const(:purge_override_result)
        )
        { :missing, nil }
    end
  end
  defp handle_take(_missing, _cache),
    do: { :missing, nil }
end
