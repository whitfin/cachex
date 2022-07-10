defmodule Cachex.Actions.ExecuteTest do
  use CachexCase

  # This test just makes sure that execution blocks are handled correctly in that
  # they can carry out many actions and return a joint result without having to
  # go back to the cache table.
  test "execution blocks can carry out many actions" do
    # create a test cache
    cache = Helper.create_cache()

    # start an execution block
    result =
      Cachex.execute(cache, fn cache ->
        [
          Cachex.put!(cache, 1, 1),
          Cachex.put!(cache, 2, 2),
          Cachex.put!(cache, 3, 3)
        ]
      end)

    # verify the block returns correct values
    assert(result == {:ok, [true, true, true]})
  end
end
