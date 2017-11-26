defmodule Cachex.Actions.CountTest do
  use CachexCase

  # This test verifies that a cache can be successfully counted. Counting a cache
  # will return the size of the cache, but ignoring the number of expired entries.
  test "counting items in a cache" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = Helper.create_cache([ hooks: [ hook ] ])

    # fill with some items
    { :ok, true } = Cachex.set(cache, 1, 1)
    { :ok, true } = Cachex.set(cache, 2, 2)
    { :ok, true } = Cachex.set(cache, 3, 3)

    # add some expired items
    { :ok, true } = Cachex.set(cache, 4, 4, ttl: 1)
    { :ok, true } = Cachex.set(cache, 5, 5, ttl: 1)
    { :ok, true } = Cachex.set(cache, 6, 6, ttl: 1)

    # let entries expire
    :timer.sleep(2)

    # clear all hook
    Helper.flush()

    # count the cache
    result = Cachex.count(cache)

    # only 3 items should come back
    assert(result == { :ok, 3 })

    # verify the hooks were updated with the count
    assert_receive({ { :count, [[]] }, ^result })
  end
end
