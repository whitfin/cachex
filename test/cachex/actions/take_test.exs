defmodule Cachex.Actions.TakeTest do
  use CachexCase

  # This test verifies that we can take keys from the cache. If a key has expired,
  # the value is not returned and the hooks are updated with an eviction. If the
  # key is missing, we return a message stating as such.
  test "taking keys from a cache" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = Helper.create_cache([ hooks: [ hook ] ])

    # set some keys in the cache
    { :ok, true } = Cachex.put(cache, 1, 1)
    { :ok, true } = Cachex.put(cache, 2, 2, ttl: 1)

    # wait for the TTL to pass
    :timer.sleep(2)

    # flush all existing messages
    Helper.flush()

    # take the first and second key
    result1 = Cachex.take(cache, 1)
    result2 = Cachex.take(cache, 2)

    # take a missing key
    result3 = Cachex.take(cache, 3)

    # verify the first key is retrieved
    assert(result1 == { :ok, 1 })

    # verify the second and third keys are missing
    assert(result2 == { :ok, nil })
    assert(result3 == { :ok, nil })

    # assert we receive valid notifications
    assert_receive({ { :take, [ 1, [ ] ] }, ^result1 })
    assert_receive({ { :take, [ 2, [ ] ] }, ^result2 })
    assert_receive({ { :take, [ 3, [ ] ] }, ^result3 })

    # check we received valid purge actions for the TTL
    assert_receive({ { :purge, [[]] }, { :ok, 1 } })

    # ensure that the keys no longer exist in the cache
    exists1 = Cachex.exists?(cache, 1)
    exists2 = Cachex.exists?(cache, 2)
    exists3 = Cachex.exists?(cache, 3)

    # none should exist
    assert(exists1 == { :ok, false })
    assert(exists2 == { :ok, false })
    assert(exists3 == { :ok, false })
  end
end
