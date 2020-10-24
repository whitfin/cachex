defmodule Cachex.Actions.PutAndGet do
  @moduledoc false
  # Command module to enable insertion of cache entries and return inserted value immediately.
  #
  # This is the extension of put operation, that change return value to three element tuple.
  #
  # This command will use lock aware contexts to ensure that there are no key
  # clashes when writing values to the cache.
  alias Cachex.Actions
  alias Cachex.Options
  alias Cachex.Services.Janitor
  alias Cachex.Services.Locksmith

  # add our macros
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Inserts a value into the cache and return it immediately (as a part of tuple).

  This takes expiration times into account before insertion and will operate
  inside a lock aware context to avoid clashing with other processes.
  """
  def execute(cache() = cache, key, value, options) do
    ttlval = Options.get(options, :ttl, &is_integer/1)
    expiry = Janitor.expiration(cache, ttlval)

    record = entry_now(key: key, ttl: expiry, value: value)

    Locksmith.write(cache, [ key ], fn ->
      t = Actions.write(cache, record)
      Tuple.append(t, value)
    end)
  end
end
