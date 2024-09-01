defmodule Cachex.Actions.TouchTest do
  use Cachex.Test.Case

  # This test ensures that we can safely update the touch time of a key without
  # affecting when the key will be removed. We verify the TTL before and after
  # to make sure that there is no impact to the TTL, but also ensure that the
  # touch time on the record has been modified.
  test "touching a key in the cache" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = TestUtils.create_cache(hooks: [hook])

    # pull back the state
    state = Services.Overseer.retrieve(cache)

    # add some keys to the cache
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, true} = Cachex.put(cache, 2, 2, ttl: 1000)

    # clear messages
    TestUtils.flush()

    # retrieve the raw records
    entry(touched: touched1, ttl: ttl1) = Cachex.Actions.read(state, 1)
    entry(touched: touched2, ttl: ttl2) = Cachex.Actions.read(state, 2)

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
    assert(touch1 == {:ok, true})
    assert(touch2 == {:ok, true})

    # the third shouldn't, as it's missing
    assert(touch3 == {:ok, false})

    # verify the hooks were updated with the message
    assert_receive({{:touch, [1, []]}, ^touch1})
    assert_receive({{:touch, [2, []]}, ^touch2})
    assert_receive({{:touch, [3, []]}, ^touch3})

    # retrieve the raw records again
    entry(touched: touched3, ttl: ttl3) = Cachex.Actions.read(state, 1)
    entry(touched: touched4, ttl: ttl4) = Cachex.Actions.read(state, 2)

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

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "adding new entries to a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, true} = Cachex.put(cache, 2, 2)

    # wait a little
    :timer.sleep(10)

    # pull back the records inserted so far
    {:ok, export1} = Cachex.export(cache)

    # sort to guarantee we're checking well
    [record1, record2] = Enum.sort(export1)

    # unpack the records touch time
    entry(touched: touched1) = record1
    entry(touched: touched2) = record2

    # now touch both keys
    {:ok, true} = Cachex.touch(cache, 1)
    {:ok, true} = Cachex.touch(cache, 2)

    # pull back the records after the touchs
    {:ok, export2} = Cachex.export(cache)

    # sort to guarantee we're checking well
    [record3, record4] = Enum.sort(export2)

    # unpack the records touch time
    entry(touched: touched3) = record3
    entry(touched: touched4) = record4

    # new touched should be larger than old
    assert(touched3 > touched1)
    assert(touched4 > touched2)
  end
end
