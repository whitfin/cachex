defmodule Cachex.Actions.TtlTest do
  use Cachex.Test.Case

  # This test verifies the responses of checking TTLs inside the cache. We make
  # sure that TTLs are calculated correctly based on nil and set TTLs. If the
  # key is missing, we return a tuple signalling such.
  test "retrieving a key TTL" do
    # create a test cache
    cache = TestUtils.create_cache()

    # set several keys in the cache
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, true} = Cachex.put(cache, 2, 2, expire: 10000)

    # verify the TTL the nil keys
    assert Cachex.ttl(cache, 1) == nil
    assert Cachex.ttl(cache, 3) == nil

    # the second should be close to 10s
    cache
    |> Cachex.ttl(2)
    |> assert_in_delta(10000, 10)
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "retrieving a key TTL in a cluster" do
    # create a new cache cluster
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    {:ok, true} = Cachex.put(cache, 1, 1, expire: 500)
    {:ok, true} = Cachex.put(cache, 2, 2, expire: 500)

    # check the expiration of each key in the cluster
    assert Cachex.ttl(cache, 1) > 450
    assert Cachex.ttl(cache, 2) > 450
  end
end
