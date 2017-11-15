defmodule Cachex.Actions.Keys do
  @moduledoc false
  # This module is in control of retrieving a list of keys from the cache. The
  # Keys action takes expiration into account and as such the query is quite slow
  # (to the point where it's probably the slowest Cachex operation). This is to
  # be expected, so use it wisely - or use a Stream instead.

  # we need our imports
  use Cachex.Actions

  # add some aliases
  alias Cachex.Cache
  alias Cachex.Util

  @doc """
  Retrieves a list of all keys in the cache.

  We only return the keys for items which have not yet expired. This means that
  if there are items currently inside the cache which are set to be removed by
  the next purge call, they will not be included in this count.

  There are currently no recognised options, the argument only exists for future
  proofing.
  """
  defaction keys(%Cache{ name: name } = cache, options) do
    query = Util.retrieve_all_rows(:key)
    klist = :ets.select(name, query)

    { :ok, klist }
  end
end
