defmodule Cachex.Actions.ExecuteTest do
  use CachexCase

  # This test just makes sure that execution blocks are handled correctly in that
  # they can carry out many actions and return a joint result without having to
  # go back to the state table.
  test "execution blocks can carry out many actions" do
    # create a test cache
    cache = Helper.create_cache()

    # start an execution block
    result = Cachex.execute(cache, fn(%Cachex.State{ } = state) ->
      [
        Cachex.set!(state, 1, 1),
        Cachex.set!(state, 2, 2),
        Cachex.set!(state, 3, 3)
      ]
    end)

    # verify the block returns correct values
    assert(result == [ true, true, true ])
  end

end
