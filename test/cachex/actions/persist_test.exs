defmodule Cachex.Actions.PersistTest do
  use CachexCase

  # This test just ensures that we can safely remove expiration times from a key.
  # We set a TTL on a key and then persist it and verify that there is then no
  # TTL associated with the key going forwards.
  test "removing the TTL on a key" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = Helper.create_cache([ hooks: [ hook ] ])

    # add some keys to the cache
    { :ok, true } = Cachex.put(cache, 1, 1)
    { :ok, true } = Cachex.put(cache, 2, 2, ttl: 1000)

    # clear messages
    Helper.flush()

    # retrieve all TTLs from the cache
    ttl1 = Cachex.ttl!(cache, 1)
    ttl2 = Cachex.ttl!(cache, 2)

    # the first TTL should be nil
    assert(ttl1 == nil)

    # the second TTL should be roughly 1000
    assert_in_delta(ttl2, 995, 6)

    # remove the TTLs
    persist1 = Cachex.persist(cache, 1)
    persist2 = Cachex.persist(cache, 2)
    persist3 = Cachex.persist(cache, 3)

    # the first two writes should succeed
    assert(persist1 == { :ok, true })
    assert(persist2 == { :ok, true })

    # the third shouldn't, as it's missing
    assert(persist3 == { :ok, false })

    # verify the hooks were updated with the message
    assert_receive({ { :persist, [ 1, [] ] }, ^persist1 })
    assert_receive({ { :persist, [ 2, [] ] }, ^persist2 })
    assert_receive({ { :persist, [ 3, [] ] }, ^persist3 })

    # retrieve all TTLs from the cache
    ttl3 = Cachex.ttl!(cache, 1)
    ttl4 = Cachex.ttl!(cache, 2)

    # both TTLs should now be nil
    assert(ttl3 == nil)
    assert(ttl4 == nil)
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "removing the TTL on a key in a cluster" do
    # create a new cache cluster
    { cache, _nodes } = Helper.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    { :ok, true } = Cachex.put(cache, 1, 1, [ ttl: 5000 ])
    { :ok, true } = Cachex.put(cache, 2, 2, [ ttl: 5000 ])

    # remove expirations on both keys
    { :ok, true } = Cachex.persist(cache, 1)
    { :ok, true } = Cachex.persist(cache, 2)

    # check the expiration of each key in the cluster
    { :ok, expiration1 } = Cachex.ttl(cache, 1)
    { :ok, expiration2 } = Cachex.ttl(cache, 2)

    # both have an expiration
    assert(expiration1 == nil)
    assert(expiration2 == nil)
  end
end
