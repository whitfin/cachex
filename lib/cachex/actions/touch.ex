defmodule Cachex.Actions.Touch do
  @moduledoc false
  # Command module to update the touch time of cache entries.
  #
  # Touching an entry is the act of resetting the touch time to the current
  # time, without affecting the expiration set against the record. As such
  # it's incredibly useful for implementing least-recently used caching
  # systems without breaking expiration based contracts.
  alias Cachex.Actions
  alias Cachex.Services.Locksmith
  alias Actions.Ttl

  # we need our imports
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Updates the touch time of an entry inside a cache.

  Touching an entry will update the write time of the entry, but without modifying any
  expirations set on the entry. This is done by reading back the current expiration,
  and then updating the record appropriately to modify the touch time and setting the
  expiration to the offset of the two.
  """
  def execute(cache() = cache, key, _options) do
    Locksmith.transaction(cache, [key], fn ->
      cache
      |> Ttl.execute(key, [])
      |> handle_expiration(cache, key)
    end)
  end

  ###############
  # Private API #
  ###############

  # Handles the result of the TTL call.
  #
  # If the expiration if unset, we update just the touch time insude the entry
  # as we don't have to account for the offset. If an expiration is set, we
  # also update the expiration on the record to be the returned offset.
  defp handle_expiration({:ok, value}, cache, key) do
    Actions.update(
      cache,
      key,
      case value do
        nil -> entry_mod_now()
        exp -> entry_mod_now(expiration: exp)
      end
    )
  end
end
