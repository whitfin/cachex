defmodule Cachex.Actions.UpdateTest do
  use Cachex.Test.Case

  # This test just ensures that we can update the value associated with a key
  # when the value already exists inside the cache. We make sure that any TTL
  # associated with the key remains unchanged (as the record is being modified,
  # not overwritten).
  test "updates against an existing key" do
    # create a test cache
    cache = TestUtils.create_cache()

    # set a value with no TTL inside the cache
    {:ok, true} = Cachex.put(cache, 1, 1)

    # set a value with a TTL in the cache
    {:ok, true} = Cachex.put(cache, 2, 2, expire: 10000)

    # attempt to update both keys
    assert Cachex.update(cache, 1, 3)
    assert Cachex.update(cache, 2, 3)

    # retrieve the modified keys
    assert Cachex.get(cache, 1) == 3
    assert Cachex.get(cache, 2) == 3

    # the first TTL should still be unset
    assert Cachex.ttl(cache, 1) == nil

    # the second should still be set
    cache
    |> Cachex.ttl!(2)
    |> assert_in_delta(10000, 10)
  end

  # This test just verifies that we successfully return an error when we try to
  # update a value which does not exist inside the cache.
  test "updates against a missing key" do
    # create a test cache
    cache = TestUtils.create_cache()

    # attempt to update a missing key in the cache
    refute Cachex.update(cache, 1, 3)
    refute Cachex.update(cache, 2, 3)
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "updating a key in a cache cluster" do
    # create a new cache cluster
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    {:ok, true} = Cachex.put(cache, 1, 1, expire: 500)
    {:ok, true} = Cachex.put(cache, 2, 2, expire: 500)

    # run updates against both keys
    assert Cachex.update(cache, 1, -1)
    assert Cachex.update(cache, 2, -2)

    # try to retrieve both of the set keys
    assert Cachex.get(cache, 1) == -1
    assert Cachex.get(cache, 2) == -2
  end
end
