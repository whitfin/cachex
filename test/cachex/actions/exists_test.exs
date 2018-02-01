defmodule Cachex.Actions.ExistsTest do
  use CachexCase

  # This test verifies whether a key exists in a cache. If it does, we return
  # true. If not we return false. If the key has expired, we return false and
  # evict it on demand using the generic read action.
  test "checking if a key exists" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = Helper.create_cache([ hooks: [ hook ] ])

    # add some keys to the cache
    { :ok, true } = Cachex.put(cache, 1, 1)
    { :ok, true } = Cachex.put(cache, 2, 2, ttl: 1)

    # let TTLs clear
    :timer.sleep(2)

    # clear messages
    Helper.flush()

    # check if several keys exist
    exists1 = Cachex.exists?(cache, 1)
    exists2 = Cachex.exists?(cache, 2)
    exists3 = Cachex.exists?(cache, 3)

    # the first result should exist
    assert(exists1 == { :ok, true })

    # the next two should be missing
    assert(exists2 == { :ok, false })
    assert(exists3 == { :ok, false })

    # verify the hooks were updated with the message
    assert_receive({ { :exists?, [ 1, [] ] }, ^exists1 })
    assert_receive({ { :exists?, [ 2, [] ] }, ^exists2 })
    assert_receive({ { :exists?, [ 3, [] ] }, ^exists3 })

    # check we received valid purge actions for the TTL
    assert_receive({ { :purge, [[]] }, { :ok, 1 } })

    # retrieve all values from the cache
    value1 = Cachex.get(cache, 1)
    value2 = Cachex.get(cache, 2)
    value3 = Cachex.get(cache, 3)

    # verify the second was removed
    assert(value1 == { :ok, 1 })
    assert(value2 == { :missing, nil })
    assert(value3 == { :missing, nil })
  end
end
