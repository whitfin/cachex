defmodule Cachex.Actions.Import do
  @moduledoc false
  # Command module to allow import cache entries from a list.
  #
  # This command should be considered expensive and should be use sparingly. Due
  # to the requirement of being compatible with distributed caches, this cannot
  # use a simple `put_many/4` call; rather it needs to walk the full list. It's
  # provided because it's the backing implementation of the `load/3` command.
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Imports all cache entries from a list into a cache.

  This action should only be used in the case of exports and/or debugging, due
  to the memory overhead involved, as well as the potential slowness of walking
  a large import set.
  """
  def execute(cache() = cache, entries, _options),
    do: {Enum.each(entries, &import(cache, &1, now())), true}

  # Imports an entry directly when no TTL is included.
  #
  # As this is a direct import, we just use `Cachex.put/4` with the provided
  # key and value from the existing entry record - nothing special here.
  defp import(cache, entry(key: k, ttl: nil, value: v), _time),
    do: {:ok, true} = Cachex.put(cache, k, v, const(:notify_false))

  # Skips over entries which have already expired.
  #
  # This occurs in the case there was an existing touch time and TTL, and
  # the expiration time would already have passed (so there's no point in
  # adding the record to the cache just to throw it away in future).
  defp import(_cache, entry(modified: m, ttl: t2), time)
       when m + t2 < time,
       do: nil

  # Imports an entry, using the current time to offset the TTL value.
  #
  # This is required to shift the TTLs set in a backup to match the current
  # import time, so that the rest of the lifetime of the key is the same. If
  # we didn't do this, the key would live longer in the cache than intended.
  defp import(cache, entry(key: k, modified: m, ttl: t2, value: v), time) do
    opts = const(:notify_false) ++ [ttl: m + t2 - time]
    {:ok, true} = Cachex.put(cache, k, v, opts)
  end
end
