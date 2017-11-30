defmodule Cachex.Actions.Refresh do
  @moduledoc false
  # This module controls the implementation of the Refresh action. Refreshing is
  # the act of resetting a TTL as if it has just been set. We accomplish this by
  # simply updating the touch time (as this is that the TTL is calculated from).
  # The Refresh action executes in a lock-aware context which ensures consistency
  # against Transactions.

  # we need our imports
  import Cachex.Actions
  import Cachex.Spec

  # add some aliases
  alias Cachex.Actions
  alias Cachex.Services.Locksmith

  @doc """
  Refreshes a TTL in the cache.

  If a TTL is not set, it is left unset. Otherwise the touch time is updated to
  the current time (as expiration is a function of touch time and TTL time).

  We execute inside a lock-aware context to ensure that no other operation is
  working on the same keys during execution.
  """
  defaction refresh(cache() = cache, key, options) do
    Locksmith.write(cache, key, fn ->
      Actions.update(cache, key, entry_mod_now())
    end)
  end
end
