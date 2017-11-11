defmodule Cachex.Actions.Clear do
  @moduledoc false
  # This module controls the action of clearing a cache. Clearing a cache means
  # removing all items from inside the cache, regardless of whether they should
  # have been evicted or not.

  # we need our imports
  use Cachex.Actions

  # add some aliases
  alias Cachex.Actions.Size
  alias Cachex.Services.Locksmith
  alias Cachex.State

  @doc """
  Clears all items in a cache.

  We return the number of items current inside the cache when we clear it. This
  action executes inside a Transaction to ensure that there are no keys currently
  under a lock - thus ensuring consistency.

  There are currently no recognised options, the argument only exists for future
  proofing.
  """
  defaction clear(%State{ cache: cache } = state, options) do
    Locksmith.transaction(state, [], fn ->
      evicted =
        state
        |> Size.execute(@notify_false)
        |> handle_evicted

      true = :ets.delete_all_objects(cache)

      evicted
    end)
  end

  # Handles the result of the size call and transforms the result into something
  # we can safely return to the user to represent how many items were cleared.
  defp handle_evicted({ :ok, _size } = res),
    do: res
  defp handle_evicted(_other_result),
    do: { :ok, 0 }
end
