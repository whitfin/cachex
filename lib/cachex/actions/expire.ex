defmodule Cachex.Actions.Expire do
  @moduledoc false
  # This module controls the implementation of the Expire action. Expiring has
  # to deal with several scenarios, including the removal of an expiration (as
  # `:expire` is used as a delegate for `:persist`). The Expire action executes
  # in a lock-aware context which ensures consistency against Transactions.

  # we need our imports
  import Cachex.Actions
  import Cachex.Spec

  # add some aliases
  alias Cachex.Actions
  alias Cachex.Actions.Del
  alias Cachex.Cache
  alias Cachex.Services.Locksmith
  alias Cachex.Util

  @doc """
  Sets the expiration time on a given record.

  If the expiration time is negative, we immediately remove the record from the
  cache due to a purge. If it's non-negative, we set the touch time to be the
  current time and the TTL to be the given expire time. If the expiration is nil,
  this means we need to remove the TTL, and so we remove the TTL field by setting
  it to nil. This is done implicitly through the fact that `nil > -1 == true`.

  This action executes inside a Transaction to ensure that there are no keys currently
  under a lock - thus ensuring consistency.

  There are currently no recognised options, the argument only exists for future
  proofing.
  """
  defaction expire(%Cache{ } = cache, key, expiration, options) do
    Locksmith.write(cache, key, fn ->
      do_expire(cache, key, expiration)
    end)
  end

  # Carries out the required actions to control an expiration. If the expiration
  # given is `nil` or a non-negative, we update the record's touch time and TTL.
  # If the value is negative, we immediately remove the record from the cache.
  defp do_expire(cache, key, exp) when exp > -1,
    do: Actions.update(cache, key, entry_mod(touched: Util.now, ttl: exp))
  defp do_expire(cache, key, _exp),
    do: Del.execute(cache, key, const(:purge_override))
end
