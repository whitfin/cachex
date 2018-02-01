defmodule Cachex.Actions.PutMany do
  @moduledoc """
  Command module to enable batch insertion of cache entries.

  This is an alternative entry point for adding new entries to the cache,
  specifically in the case of multiple entries at the same time. Performance
  is enhanced in this use case, but lowered in the case of single entries.

  This command will use lock aware contexts to ensure that there are no key
  clashes when writing values to the cache.
  """
  alias Cachex.Actions
  alias Cachex.Options
  alias Cachex.Services.Janitor
  alias Cachex.Services.Locksmith

  # add our macros
  import Cachex.Actions
  import Cachex.Errors
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Inserts a batch of values into the cache.

  This takes expiration times into account before insertion and will operate
  inside a lock aware context to avoid clashing with other processes.
  """
  defaction put_many(cache() = cache, pairs, options) do
    ttlval = Options.get(options, :ttl, &is_integer/1)
    expiry = Janitor.expiration(cache, ttlval)

    with { :ok, keys, entries } <- map_entries(expiry, pairs, [], []) do
      Locksmith.write(cache, keys, fn ->
        Actions.write(cache, entries)
      end)
    end
  end

  ###############
  # Private API #
  ###############

  # Generates keys/entries from the provided list of pairs.
  #
  # Pairs must be Tuples of two, a key and a value. The keys will be
  # buffered into a list to be used to handle locking, whilst entries
  # will also be buffered into a batch of writes.
  #
  # If an unexpected pair is hit, an error will be returned and no
  # values will be written to the backing table.
  defp map_entries(ttl, [ { key, value } | pairs ], keys, entries) do
    entry = entry_now(key: key, ttl: ttl, value: value)
    map_entries(ttl, pairs, [ key | keys ], [ entry | entries ])
  end
  defp map_entries(_ttl, [], [], _entries),
    do: { :ok, false }
  defp map_entries(_ttl, [], keys, entries),
    do: { :ok, keys, entries }
  defp map_entries(_ttl, _inv, _keys, _entries),
    do: error(:invalid_pairs)
end
