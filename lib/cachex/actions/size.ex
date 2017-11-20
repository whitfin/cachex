defmodule Cachex.Actions.Size do
  @moduledoc false
  # This module contains the implementation of the Size action, which simply
  # uses the built in ETS info commands to retrieve the number of records currently
  # inside the cache. Expirations are not taken into account here.

  # we need our imports
  use Cachex.Include,
    actions: true

  # add some aliases
  alias Cachex.Cache

  @doc """
  Retrieve the size of the cache.

  Expirations do not matter at this point, the size purely represents the number
  of records which currently populate the cache. If you need a count taking the
  expiration into account, please use the Count action.

  There are currently no recognised options, the argument only exists for future
  proofing.
  """
  defaction size(%Cache{ name: name } = cache, options),
    do: { :ok, :ets.info(name, :size) }
end
