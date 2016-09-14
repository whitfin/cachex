defmodule Cachex.Actions.EmptyTest do
  use CachexCase

  # This test verifies that a cache is empty. We first check that it is before
  # adding any items, and after we add some we check that it's no longer empty.
  # Hook messages are represented as size calls, as empty is purely sugar on top
  # of the size functionality.
  test "checking if a cache is empty" do
    # create a forwarding hook
    hook = ForwardHook.create(%{ results: true })

    # create a test cache
    cache = Helper.create_cache([ hooks: [ hook ] ])

    # check if the cache is empty
    result1 = Cachex.empty?(cache)

    # it should be
    assert(result1 == { :ok, true })

    # verify the hooks were updated with the message
    assert_receive({ { :empty?, [[]] }, ^result1 })

    # add some cache entries
    { :ok, true } = Cachex.set(cache, 1, 1)

    # check if the cache is empty
    result2 = Cachex.empty?(cache)

    # it shouldn't be
    assert(result2 == { :ok, false })

    # verify the hooks were updated with the message
    assert_receive({ { :empty?, [[]] }, ^result2 })
  end

end
