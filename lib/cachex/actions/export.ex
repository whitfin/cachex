defmodule Cachex.Actions.Export do
  @moduledoc false
  # Command module to allow exporting all cache entries as a list.
  #
  # This command is extremely expensive as it turns the entire cache table into
  # a list, and so should be used sparingly. It's provided purely because it's
  # the backing implementation of the `dump/3` command.
  alias Cachex.Actions.Stream, as: CachexStream
  alias Cachex.Query

  # add required imports
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
  def execute(cache() = cache, options) do
    query = Query.create()
    batch = Keyword.take(options, [:batch_size])

    with {:ok, stream} <- CachexStream.execute(cache, query, batch) do
      {:ok, Enum.to_list(stream)}
    end
  end
end
