defmodule Cachex.Actions.Clear do
  @moduledoc false
  # Command module to allow the clearing of a cache.
  #
  # Clearing a cache means removing all items from inside the cache, regardless
  # of whether they should have been evicted or not.
  alias Cachex.Actions.Size
  alias Cachex.Services.Locksmith

  # import needed macros
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Clears all items in a cache.

  The number of items removed from the cache will be returned to the caller, to
  make it clear exactly how much work each call it doing.

  This action executes inside a transaction to ensure that there are no keys under
  a lock - thus ensuring consistency (any locks are executed sequentially).
  """
  def execute(cache(name: name) = cache, _options) do
    Locksmith.transaction(cache, [], fn ->
      evicted = Size.execute(cache, [])

      true = :ets.delete_all_objects(name)

      evicted
    end)
  end
end
