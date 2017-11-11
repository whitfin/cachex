defmodule Cachex.Actions.Size do
  @moduledoc false
  # This module contains the implementation of the Size action, which simply
  # uses the built in ETS info commands to retrieve the number of records currently
  # inside the cache. Expirations are not taken into account here.

  # we need our imports
  use Cachex.Actions

  # add some aliases
  alias Cachex.State

  @doc """
  Retrieve the size of the cache.

  Expirations do not matter at this point, the size purely represents the number
  of records which currently populate the cache. If you need a count taking the
  expiration into account, please use the Count action.

  There are currently no recognised options, the argument only exists for future
  proofing.
  """
  defaction size(%State{ cache: cache } = state, options) do
    { :ok, :ets.info(cache, :size) }
  end
end
