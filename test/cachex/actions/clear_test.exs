defmodule Cachex.Actions.ClearTest do
  use CachexCase

  # This test verifies that a cache can be successfully cleared. We fill the cache
  # and clear it, verifying that the entries were removed successfully. We also
  # ensure that hooks were updated with the correct values.
  test "clearing a cache of all items" do
    # create a forwarding hook
    hook = ForwardHook.create(%{ results: true })

    # create a test cache
    cache = Helper.create_cache([ hooks: [ hook ] ])

    # fill with some items
    { :ok, true } = Cachex.set(cache, 1, 1)
    { :ok, true } = Cachex.set(cache, 2, 2)
    { :ok, true } = Cachex.set(cache, 3, 3)

    # clear all hook
    Helper.flush()

    # clear the cache
    result = Cachex.clear(cache)

    # 3 items should have been removed
    assert(result == { :ok, 3 })

    # verify the hooks were updated with the clear
    assert_receive({ { :clear, [[]] }, ^result })

    # verify the size call never notified
    refute_receive({ {  :size, [[]] }, ^result })

    # retrieve all items
    value1 = Cachex.get(cache, 1)
    value2 = Cachex.get(cache, 2)
    value3 = Cachex.get(cache, 3)

    # verify the items are gone
    assert(value1 == { :missing, nil })
    assert(value2 == { :missing, nil })
    assert(value3 == { :missing, nil })
  end

end
