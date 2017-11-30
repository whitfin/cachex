defmodule Cachex.Actions.Del do
  @moduledoc false
  # This module contains the implementation of the delete action, which removes
  # a given entry from the cache. The Del action executes in a lock-aware way
  # which ensures consistency against Transactions.

  # we need our imports
  import Cachex.Actions
  import Cachex.Spec

  # add some aliases
  alias Cachex.Services.Locksmith

  @doc """
  Removes a given item from the cache.

  This function will always return a truthy response, which signals that regardless
  of whether the key existed in the cache previously, it is guaranteed to not
  exist any longer.

  We execute the delete calls under a Locksmith context to ensure that we're
  respective of any Transaction locks currently being held against the key.

  There are currently no recognised options, the argument only exists for future
  proofing.
  """
  defaction del(cache(name: name) = cache, key, options) do
    Locksmith.write(cache, key, fn ->
      { :ok, :ets.delete(name, key) }
    end)
  end
end
