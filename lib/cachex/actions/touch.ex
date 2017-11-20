defmodule Cachex.Actions.Touch do
  @moduledoc false
  # This module contains the implementation of the Touch action. Touching a key
  # is resetting the write time on a key to the current time, without affecting
  # the TTL set against the record. It is incredibly useful for implementing
  # least-recently used cache systems.

  # we need our imports
  use Cachex.Include,
    actions: true,
    constants: true

  # add some aliases
  alias Cachex.Actions
  alias Cachex.Actions.Ttl
  alias Cachex.Cache
  alias Cachex.Services.Locksmith
  alias Cachex.Util

  @doc """
  Touches a key inside the cache.

  Touching a key will update the write time of the key, but without modifying the
  TTL. This is done by reading back the current TTL, and then updating the record
  appropriately to modify the touch time and setting the TTL to being the time
  remaining.

  We execute inside a Transaction to ensure that nothing modifies the key we're
  working with between the reading of the TTL and the update call. At a glance it
  may seem that we get away with this, but a set with a different TTL between
  when we read the TTL and when we update would cause a race condition.

  There are currently no recognised options, the argument only exists for future
  proofing.
  """
  defaction touch(%Cache{ } = cache, key, options) do
    Locksmith.transaction(cache, [ key ], fn ->
      cache
      |> Ttl.execute(key, @notify_false)
      |> handle_ttl(cache, key)
    end)
  end

  # Handles the result of the TTL call. If the TTL is unset, we simply update the
  # touch time inside the record as we don't need to care about the TTL. If the
  # TTL is set, we need to udpate the touch time to the current time, and then
  # also update the TTL to the time remaining (so there is no change in TTL when
  # the touch time changes). If the TTL returns missing we just return a false
  # to the use to signify that the key was not touched because it was missing.
  defp handle_ttl({ :ok, nil }, cache, key),
    do: Actions.update(cache, key, [{ 2, Util.now() }])
  defp handle_ttl({ :ok, val }, cache, key),
    do: Actions.update(cache, key, [{ 2, Util.now() }, { 3, val }])
  defp handle_ttl({ :missing, nil }, _cache, _key),
    do: { :missing, false }
end
