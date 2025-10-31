defmodule Cachex.Actions.Size do
  @moduledoc false
  # Command module to allow cache size retrieval.
  #
  # This command uses the built in ETS utilities to retrieve the number of
  # entries currently in the backing cache table.
  #
  # A cache's size does not take expiration times into account by default,
  # as the true size can hold records which haven't been purged yet. This
  # can be controlled via options to this action.
  import Cachex.Spec

  # add some aliases
  alias Cachex.Options
  alias Cachex.Query

  ##############
  # Public API #
  ##############

  @doc """
  Retrieves the size of the cache.

  You can use the `:expired` option to determine whether record expirations
  should be taken into account. The default value of this is `:true` as it's
  a much cheaper operation.
  """
  def execute(cache(name: name), options) do
    options
    |> Options.get(:expired, &is_boolean/1, true)
    |> retrieve_count(name)
  end

  ###############
  # Private API #
  ###############

  # Retrieve the full table count.
  defp retrieve_count(true, name),
    do: :ets.info(name, :size)

  # Retrieve only the unexpired table count.
  defp retrieve_count(false, name) do
    filter = Query.unexpired()
    clause = Query.build(where: filter, output: true)

    :ets.select_count(name, clause)
  end
end
