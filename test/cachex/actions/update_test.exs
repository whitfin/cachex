defmodule Cachex.Actions.UpdateTest do
  use CachexCase

  # This test just ensures that we can update the value associated with a key
  # when the value already exists inside the cache. We make sure that any TTL
  # associated with the key remains unchanged (as the record is being modified,
  # not overwritten).
  test "updates against an existing key" do
    # create a test cache
    cache = Helper.create_cache()

    # set a value with no TTL inside the cache
    { :ok, true } = Cachex.put(cache, 1, 1)

    # set a value with a TTL in the cache
    { :ok, true } = Cachex.put(cache, 2, 2, ttl: 10000)

    # attempt to update both keys
    update1 = Cachex.update(cache, 1, 3)
    update2 = Cachex.update(cache, 2, 3)

    # ensure both succeeded
    assert(update1 == { :ok, true })
    assert(update2 == { :ok, true })

    # retrieve the modified keys
    value1 = Cachex.get(cache, 1)
    value2 = Cachex.get(cache, 2)

    # verify the updates
    assert(value1 == { :ok, 3 })
    assert(value2 == { :ok, 3 })

    # pull back the TTLs
    ttl1 = Cachex.ttl!(cache, 1)
    ttl2 = Cachex.ttl!(cache, 2)

    # the first TTL should still be unset
    assert(ttl1 == nil)

    # the second should still be set
    assert_in_delta(ttl2, 10000, 10)
  end

  # This test just verifies that we successfully return an error when we try to
  # update a value which does not exist inside the cache.
  test "updates against a missing key" do
    # create a test cache
    cache = Helper.create_cache()

    # attempt to update a missing key in the cache
    update1 = Cachex.update(cache, 1, 3)
    update2 = Cachex.update(cache, 2, 3)

    # ensure both failed
    assert(update1 == { :ok, false })
    assert(update2 == { :ok, false })
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "updating a key in a cache cluster" do
    # create a new cache cluster
    { cache, _nodes } = Helper.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    { :ok, true } = Cachex.put(cache, 1, 1, [ ttl: 500 ])
    { :ok, true } = Cachex.put(cache, 2, 2, [ ttl: 500 ])

    # run updates against both keys
    { :ok, true } = Cachex.update(cache, 1, -1)
    { :ok, true } = Cachex.update(cache, 2, -2)

    # try to retrieve both of the set keys
    updated1 = Cachex.get(cache, 1)
    updated2 = Cachex.get(cache, 2)

    # check the update occurred
    assert(updated1 == { :ok, -1 })
    assert(updated2 == { :ok, -2 })
  end
end
