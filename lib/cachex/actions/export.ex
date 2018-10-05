defmodule Cachex.Actions.Export do
  @moduledoc false
  # Command module to allow exporting all cache entries as a list.
  #
  # This command is extremely expensive as it turns the entire cache table into
  # a list, and so should be used sparingly. It's provided purely because it's
  # the backing implementation of the `dump/3` command.
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Retrieves all cache entries as a list.

  The returned list is a collection of cache entry records, which is a little
  more optimized than doing the same via `stream/3`.

  This action should only be used in the case of exports and/or debugging, due
  to the memory overhead involved, as well as the large concatenations.
  """
  def execute(cache(name: name), _options),
    do: { :ok, :ets.tab2list(name) }
end
