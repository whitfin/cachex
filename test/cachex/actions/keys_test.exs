defmodule Cachex.Actions.KeysTest do
  use CachexCase

  # This test verifies that it's possible to retrieve the keys inside a cache.
  # It should be noted that the keys function takes TTL into account and only
  # returns the keys of those records which have not expired. Order is not in
  # any way guaranteed, even with no cache modification.
  test "retrieving the keys inside the cache" do
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

    # retrieve the keys
    { status, keys } = Cachex.keys(cache)

    # ensure the status is ok
    assert(status == :ok)

    # sort the keys
    result = Enum.sort(keys)

    # only 3 items should come back
    assert(result == [ 1, 2, 3 ])

    # verify the hooks were updated with the count
    assert_receive({ { :keys, [[]] }, { ^status, ^keys } })
  end
end
