defmodule Cachex.Actions.PersistTest do
  use Cachex.Test.Case

  # This test just ensures that we can safely remove expiration times from a key.
  # We set a TTL on a key and then persist it and verify that there is then no
  # TTL associated with the key going forwards.
  test "removing the TTL on a key" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = TestUtils.create_cache(hooks: [hook])

    # add some keys to the cache
    assert Cachex.put(cache, 1, 1)
    assert Cachex.put(cache, 2, 2, expire: 1000)

    # clear messages
    TestUtils.flush()

    # the first TTL should be nil
    assert Cachex.ttl(cache, 1) == nil

    # the second TTL should be roughly 1000
    assert_in_delta Cachex.ttl(cache, 2), 995, 6

    # remove the TTLs
    assert Cachex.persist(cache, 1)
    assert Cachex.persist(cache, 2)
    refute Cachex.persist(cache, 3)

    # verify the hooks were updated with the message
    assert_receive {{:persist, [1, []]}, true}
    assert_receive {{:persist, [2, []]}, true}
    assert_receive {{:persist, [3, []]}, false}

    # both TTLs should now be nil
    assert Cachex.ttl(cache, 1) == nil
    assert Cachex.ttl(cache, 2) == nil
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "removing the TTL on a key in a cluster" do
    # create a new cache cluster
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    assert Cachex.put(cache, 1, 1, expire: 5000)
    assert Cachex.put(cache, 2, 2, expire: 5000)

    # remove expirations on both keys
    assert Cachex.persist(cache, 1)
    assert Cachex.persist(cache, 2)

    # check the expiration of each key in the cluster
    assert Cachex.ttl!(cache, 1) == nil
    assert Cachex.ttl!(cache, 2) == nil
  end
end
