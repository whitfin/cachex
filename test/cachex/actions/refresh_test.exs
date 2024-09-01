defmodule Cachex.Actions.RefreshTest do
  use Cachex.Test.Case

  # This test verifies that we can reset the TTL time on a key. We check this
  # by settings keys with and without a TTL, waiting for some time to pass, and
  # then check and refresh the TTL. This ensures that the TTL is reset after we
  # refresh the key.
  test "refreshing the TTL time on a key" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = TestUtils.create_cache(hooks: [hook])

    # add some keys to the cache
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, true} = Cachex.put(cache, 2, 2, ttl: 1000)

    # clear messages
    TestUtils.flush()

    # wait for 25ms
    :timer.sleep(25)

    # retrieve all TTLs from the cache
    ttl1 = Cachex.ttl!(cache, 1)
    ttl2 = Cachex.ttl!(cache, 2)

    # the first TTL should be nil
    assert(ttl1 == nil)

    # the second TTL should be roughly 975
    assert_in_delta(ttl2, 970, 6)

    # refresh some TTLs
    refresh1 = Cachex.refresh(cache, 1)
    refresh2 = Cachex.refresh(cache, 2)
    refresh3 = Cachex.refresh(cache, 3)

    # the first two writes should succeed
    assert(refresh1 == {:ok, true})
    assert(refresh2 == {:ok, true})

    # the third shouldn't, as it's missing
    assert(refresh3 == {:ok, false})

    # verify the hooks were updated with the message
    assert_receive({{:refresh, [1, []]}, ^refresh1})
    assert_receive({{:refresh, [2, []]}, ^refresh2})
    assert_receive({{:refresh, [3, []]}, ^refresh3})

    # retrieve all TTLs from the cache
    ttl3 = Cachex.ttl!(cache, 1)
    ttl4 = Cachex.ttl!(cache, 2)

    # the first TTL should still be nil
    assert(ttl3 == nil)

    # the second TTL should be reset to 1000
    assert_in_delta(ttl4, 995, 10)
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "refreshing the TTL on a key in a cluster" do
    # create a new cache cluster
    {cache, _nodes} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    {:ok, true} = Cachex.put(cache, 1, 1, ttl: 500)
    {:ok, true} = Cachex.put(cache, 2, 2, ttl: 500)

    # pause to reduce the TTL a little
    :timer.sleep(250)

    # check the expiration of each key in the cluster
    {:ok, expiration1} = Cachex.ttl(cache, 1)
    {:ok, expiration2} = Cachex.ttl(cache, 2)

    # check the delta changed
    assert(expiration1 < 300)
    assert(expiration2 < 300)

    # refresh the TTL on both keys
    refresh1 = Cachex.refresh(cache, 1)
    refresh2 = Cachex.refresh(cache, 2)

    # check the refresh results
    assert(refresh1 == {:ok, true})
    assert(refresh2 == {:ok, true})

    # check the expiration of each key in the cluster
    {:ok, expiration3} = Cachex.ttl(cache, 1)
    {:ok, expiration4} = Cachex.ttl(cache, 2)

    # check the time reset
    assert(expiration3 > 300)
    assert(expiration4 > 300)
  end
end
