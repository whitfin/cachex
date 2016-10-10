defmodule Cachex.Actions.TouchTest do
  use CachexCase

  # This test ensures that we can safely update the touch time of a key without
  # affecting when the key will be removed. We verify the TTL before and after
  # to make sure that there is no impact to the TTL, but also ensure that the
  # touch time on the record has been modified.
  test "touching a key in the cache" do
    # create a forwarding hook
    hook = ForwardHook.create(%{ results: true })

    # create a test cache
    cache = Helper.create_cache([ hooks: [ hook ] ])

    # pull back the state
    state = Cachex.State.get(cache)

    # add some keys to the cache
    { :ok, true } = Cachex.set(cache, 1, 1)
    { :ok, true } = Cachex.set(cache, 2, 2, ttl: 1000)

    # clear messages
    Helper.flush()

    # retrieve the raw records
    { _key1, touched1, ttl1, _value1 } = Cachex.Actions.read(state, 1)
    { _key2, touched2, ttl2, _value2 } = Cachex.Actions.read(state, 2)

    # the first TTL should be nil
    assert(ttl1 == nil)

    # the second TTL should be roughly 1000
    assert_in_delta(ttl2, 995, 6)

    # wait for 50ms
    :timer.sleep(50)

    # touch the keys
    touch1 = Cachex.touch(cache, 1)
    touch2 = Cachex.touch(cache, 2)
    touch3 = Cachex.touch(cache, 3)

    # the first two writes should succeed
    assert(touch1 == { :ok, true })
    assert(touch2 == { :ok, true })

    # the third shouldn't, as it's missing
    assert(touch3 == { :missing, false })

    # verify the hooks were updated with the message
    assert_receive({ { :touch, [ 1, [] ] }, ^touch1 })
    assert_receive({ { :touch, [ 2, [] ] }, ^touch2 })
    assert_receive({ { :touch, [ 3, [] ] }, ^touch3 })

    # retrieve the raw records again
    { _key1, touched3, ttl3, _value1 } = Cachex.Actions.read(state, 1)
    { _key2, touched4, ttl4, _value2 } = Cachex.Actions.read(state, 2)

    # the first ttl should still be nil
    assert(ttl3 == nil)

    # the first touch time should be roughly 50ms after the first one
    assert_in_delta(touched3, touched1 + 60, 11)

    # the second ttl should be roughly 50ms lower than the first
    assert_in_delta(ttl4, ttl2 - 60, 11)

    # the second touch time should also be 50ms after the first one
    assert_in_delta(touched4, touched2 + 60, 11)

    # for good measure, retrieve the second ttl
    ttl5 = Cachex.ttl!(cache, 2)

    # it should be roughly 945ms left
    assert_in_delta(ttl5, 940, 11)
  end

end
