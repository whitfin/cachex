defmodule Cachex.Actions.ExpireTest do
  use Cachex.Test.Case

  # This test updates the expire time on a key to expire after a given period.
  # We make sure that TTLs are updated accordingly. If the period is negative,
  # the key is immediately removed. We also make sure that we can handle setting
  # expire times on missing keys.
  test "setting a key to expire after a given period" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = TestUtils.create_cache(hooks: [hook])

    # add some keys to the cache
    assert Cachex.put(cache, 1, 1)
    assert Cachex.put(cache, 2, 2, expire: 10)
    assert Cachex.put(cache, 3, 3, expire: 10)

    # clear messages
    TestUtils.flush()

    # set the expire time
    f_expire_time = 10000
    p_expire_time = -10000

    # expire several keys
    assert Cachex.expire(cache, 1, f_expire_time)
    assert Cachex.expire(cache, 2, f_expire_time)
    assert Cachex.expire(cache, 3, p_expire_time)
    refute Cachex.expire(cache, 4, f_expire_time)

    # verify the hooks were updated with the message
    assert_receive {{:expire, [1, ^f_expire_time, []]}, true}
    assert_receive {{:expire, [2, ^f_expire_time, []]}, true}
    assert_receive {{:expire, [3, ^p_expire_time, []]}, true}
    assert_receive {{:expire, [4, ^f_expire_time, []]}, false}

    # check we received valid purge actions for the removed key
    assert_receive {{:purge, [[]]}, 1}

    # verify the new TTL has taken effect
    assert_in_delta Cachex.ttl(cache, 1), 10000, 25
    assert_in_delta Cachex.ttl(cache, 2), 10000, 25

    # assert the last two keys don't exist
    assert Cachex.ttl(cache, 3) == nil
    assert Cachex.ttl(cache, 4) == nil
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "setting a key to expire after a given period in a cluster" do
    # create a new cache cluster
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    assert Cachex.put(cache, 1, 1)
    assert Cachex.put(cache, 2, 2)

    # set expirations on both keys
    assert Cachex.expire(cache, 1, 5000)
    assert Cachex.expire(cache, 2, 5000)

    # check the expiration of each key in the cluster
    assert Cachex.ttl!(cache, 1) != nil
    assert Cachex.ttl!(cache, 2) != nil
  end
end
