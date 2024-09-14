defmodule Cachex.Actions.Count do
  @moduledoc false
  # Command module to allow the counting of a cache.
  #
  # Counting a cache will make sure to take the expiration time of items into
  # consideration, making the semantics different to those of the `size()` calls.
  alias Cachex.Query

  # import needed macros
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Counts the number of items in a cache.

  This will only return the number of items which have not yet expired; this
  means that any items set to be removed in the next purge will not be added
  to the count. Lazy expiration does not apply to this call.
  """
  def execute(cache(name: name), _options) do
    filter = Query.unexpired()
    clause = Query.build(where: filter, output: true)

    {:ok, :ets.select_count(name, clause)}
  end
end
