defmodule Cachex.Actions.Set do
  @moduledoc false
  # This module contains the implementation of the set action. Internally we
  # convert the provided value and TTL to a record and insert it into the cache.
  # Naturally this happens inside a lock context to be sure there are no key
  # clashes.

  # we need our imports
  import Cachex.Actions
  import Cachex.Spec

  # add some aliases
  alias Cachex.Actions
  alias Cachex.Cache
  alias Cachex.Services.Locksmith
  alias Cachex.Util

  @doc """
  Sets a value inside the cache.

  Naturally this executes in a lock context to ensure that there are no other
  write operations currently happening on the key. We calculate the record to
  write outside of the lock context just to avoid potentially blocking the backing
  Transaction manager process for more time than is needed.
  """
  defaction set(%Cache{ } = cache, key, value, options) do
    ttlval = Util.get_opt(options, :ttl, &is_integer/1)
    expiry = Util.get_expiration(cache, ttlval)

    record = entry_now(key: key, ttl: expiry, value: value)

    Locksmith.write(cache, key, fn ->
      Actions.write(cache, record)
    end)
  end
end
