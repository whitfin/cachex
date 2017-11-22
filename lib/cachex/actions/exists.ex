defmodule Cachex.Actions.Exists do
  @moduledoc false
  # This module controls the implementation behind checking whether a record
  # exists inside the cache. It's a little more complicated than just checking
  # cache membership, because we also need to take TTL into account.

  # we need our imports
  import Cachex.Actions

  # add some aliases
  alias Cachex.Actions
  alias Cachex.Cache

  @doc """
  Checks if an item exists in a cache.

  We simply return true of false if membership is detected. This operation has
  to do a read in order to validate that the TTL has expired, so we delegate to
  the generic read action to do the lifting for us.

  There are currently no recognised options, the argument only exists for future
  proofing.
  """
  defaction exists?(%Cache{ } = cache, key, options),
    do: { :ok, Actions.read(cache, key) != nil }
end
