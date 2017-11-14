defmodule Cachex.Actions.Count do
  @moduledoc false
  # This module provides the action dedicated to counting the number of items
  # which currently exist in the cache. The Count action makes sure to take the
  # expiration time of items into consideration when returning this count.

  # we need our imports
  use Cachex.Actions

  # add some aliases
  alias Cachex.State
  alias Cachex.Util

  @doc """
  Counts the number of items in a cache.

  We only return the number of items which have not yet expired. This means that
  if there are items currently inside the cache which are set to be removed by
  the next purge call, they will not be included in this count.

  There are currently no recognised options, the argument only exists for future
  proofing.
  """
  defaction count(%State{ cache: cache } = state, options) do
    query = Util.retrieve_all_rows(true)
    count = :ets.select_count(cache, query)

    { :ok, count }
  end
end
