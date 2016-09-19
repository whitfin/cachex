defmodule Cachex.Actions.Take do
  @moduledoc false
  # This module contains the implementation of the Take action. Taking a key is
  # the act of retrieving a key and deleting it in one atomic action. It's a
  # useful action when used to guarantee that a given process retrieves the last
  # known value of a record. Taking a key is clearly destructive, so it operates
  # in a lock context.

  # we need our imports
  use Cachex.Actions

  # add some aliases
  alias Cachex.Hook
  alias Cachex.LockManager
  alias Cachex.State
  alias Cachex.Util

  @doc """
  Takes a given item from the cache.

  This will always remove the value if it exists, ensuring that immediately after
  this call the value no longer exists in the cache. We uphold any expirations
  by detecting them and not returning the value if we're received one.

  Taking a value happens under a lock context to ensure that the key isn't being
  currently locked by another write sequence.

  There are currently no recognised options, the argument only exists for future
  proofing.
  """
  defaction take(%State{ cache: cache } = state, key, options) do
    LockManager.write(state, key, fn ->
      cache
      |> :ets.take(key)
      |> handle_take(state)
    end)
  end

  # Handles the result of taking a key from the cache. If the record comes back,
  # we check for expiration - if it has expired, we notify of a purge call to
  # make clear that it was correctly evicted (we don't have to remove it because
  # taking it from the cache removes it). If no value comes back, we just jump
  # to returning a missing result and a nil value.
  defp handle_take([{ _key, touched, ttl, value }], %State{ cache: cache } = state) do
    if Util.has_expired?(state, touched, ttl) do
      Hook.broadcast(cache, @purge_override_call, @purge_override_result)
      { :missing, nil }
    else
      { :ok, value }
    end
  end
  defp handle_take(_missing, _state) do
    { :missing, nil }
  end

end
