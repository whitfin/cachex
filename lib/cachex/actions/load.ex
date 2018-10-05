defmodule Cachex.Actions.Load do
  @moduledoc false
  # Command module to allow deserialization of a cache from disk.
  #
  # Loading a cache from disk requires that it was previously dumped using the
  # `dump()` command (it does not support loading from DETS). Most of the heavy
  # lifting inside this command is done via the `Cachex.Disk` module.
  alias Cachex.Disk

  # we need our imports
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Loads a previously dumped cache from a file.

  If there are any issues reading the file, an error will be returned. Only files
  which were created via `dump` can be loaded, and the load will detect any disk
  compression automatically.

  Loading a backup will merge the file into the provided cache, overwriting any
  clashes. If you wish to empty the cache and then import your backup, you can
  use a transaction and clear the cache before loading the backup.
  """
  def execute(cache() = cache, path, options) do
    with { :ok, entries } <- Disk.read(path, options) do
      { Enum.each(entries, &import(cache, &1, now())), true }
    end
  end

  # Imports an entry directly when no TTL is included.
  #
  # As this is a direct import, we just use `Cachex.put/4` with the provided
  # key and value from the existing entry record - nothing special here.
  defp import(cache, entry(key: k, ttl: nil, value: v), _time),
    do: { :ok, true } = Cachex.put(cache, k, v, const(:notify_false))

  # Skips over entries which have already expired.
  #
  # This occurs in the case there was an existing touch time and TTL, and
  # the expiration time would already have passed (so there's no point in
  # adding the record to the cache just to throw it away in future).
  defp import(_cache, entry(touched: t1, ttl: t2), time)
  when t1 + t2 < time,
    do: nil

  # Imports an entry, using the current time to offset the TTL value.
  #
  # This is required to shift the TTLs set in a backup to match the current
  # import time, so that the rest of the lifetime of the key is the same. If
  # we didn't do this, the key would live longer in the cache than intended.
  defp import(cache, entry(key: k, touched: t1, ttl: t2, value: v), time) do
    { :ok, true } = Cachex.put(cache, k, v, const(:notify_false) ++ [
      ttl: (t1 + t2) - time
    ])
  end
end
