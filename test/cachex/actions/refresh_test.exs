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
    assert Cachex.put(cache, 1, 1)
    assert Cachex.put(cache, 2, 2, expire: 1000)

    # clear messages
    TestUtils.flush()

    # wait for 25ms
    :timer.sleep(25)

    # the first TTL should be nil
    assert Cachex.ttl(cache, 1) == nil

    # the second TTL should be roughly 975
    assert_in_delta Cachex.ttl(cache, 2), 970, 6

    # refresh some TTLs
    assert Cachex.refresh(cache, 1)
    assert Cachex.refresh(cache, 2)
    refute Cachex.refresh(cache, 3)

    # verify the hooks were updated with the message
    assert_receive {{:refresh, [1, []]}, true}
    assert_receive {{:refresh, [2, []]}, true}
    assert_receive {{:refresh, [3, []]}, false}

    # the first TTL should still be nil
    assert Cachex.ttl(cache, 1) == nil

    # the second TTL should be reset to 1000
    assert_in_delta Cachex.ttl(cache, 2), 995, 10
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "refreshing the TTL on a key in a cluster" do
    # create a new cache cluster
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    assert Cachex.put(cache, 1, 1, expire: 500)
    assert Cachex.put(cache, 2, 2, expire: 500)

    # pause to reduce the TTL a little
    :timer.sleep(250)

    # check the expiration of each key in the cluster
    assert Cachex.ttl!(cache, 1) < 300
    assert Cachex.ttl!(cache, 2) < 300

    # refresh the TTL on both keys
    assert Cachex.refresh(cache, 1)
    assert Cachex.refresh(cache, 2)

    # check the time reset
    assert Cachex.ttl(cache, 1) > 300
    assert Cachex.ttl(cache, 2) > 300
  end
end
