defmodule Cachex.Actions.Size do
  @moduledoc false
  # Command module to allow cache size retrieval.
  #
  # This command uses the built in ETS utilities to retrieve the number of
  # entries currently in the backing cache table.
  #
  # Retrieving the size of the cache won't take expiration times into account;
  # if this is desired the `count()` command should be used instead. The main
  # advantage here is that this is O(1) at the cost of accuracy.
  import Cachex.Actions
  import Cachex.Spec

  @doc """
  Retrieves the size of the cache.

  The size represents the total size of the internal keyspace, ignoring any
  expirations set on entries. As such, this call is O(1) rather than the
  more expensive O(N) used by `count()`. Which you use depends on exactly
  what you want the returned number to represent.
  """
  defaction size(cache(name: name) = cache, options),
    do: { :ok, :ets.info(name, :size) }
end
