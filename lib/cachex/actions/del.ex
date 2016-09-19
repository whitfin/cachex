defmodule Cachex.Actions.Del do
  @moduledoc false
  # This module contains the implementation of the delete action, which removes
  # a given entry from the cache. The Del action executes in a lock-aware way
  # which ensures consistency against Transactions.

  # we need our imports
  use Cachex.Actions

  # add some aliases
  alias Cachex.LockManager
  alias Cachex.State

  @doc """
  Removes a given item from the cache.

  This function will always return a truthy response, which signals that regardless
  of whether the key existed in the cache previously, it is guaranteed to not
  exist any longer.

  We execute the delete calls under a LockManager context to ensure that we're
  respective of any Transaction locks currently being held against the key.

  There are currently no recognised options, the argument only exists for future
  proofing.
  """
  defaction del(%State{ cache: cache } = state, key, options) do
    LockManager.write(state, key, fn ->
      { :ok, :ets.delete(cache, key) }
    end)
  end

end
