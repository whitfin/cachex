defmodule Cachex.Actions.Count do
  @moduledoc false
  # Command module to allow the counting of a cache.
  #
  # Counting a cache will make sure to take the expiration time of items into
  # consideration, making the semantics different to those of the `size()` calls.
  alias Cachex.Query

  # import needed macros
  import Cachex.Actions
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
  defaction count(cache(name: name) = cache, options),
    do: { :ok, :ets.select_count(name, Query.create_unexpired_query(true)) }
end
