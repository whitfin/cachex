defmodule Cachex.Actions.PutTest do
  use Cachex.Test.Case

  # This test verifies the addition of new entries to the cache. We ensure that
  # values can be added and can be given expiration values. We also test the case
  # in which a cache has a default expiration value, and the ability to override
  # this as necessary.
  test "adding new values to the cache" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache1 = TestUtils.create_cache(hooks: [hook])

    # create a test cache with a default ttl
    cache2 =
      TestUtils.create_cache(
        hooks: [hook],
        expiration: expiration(default: 10000)
      )

    # set some values in the cache
    assert Cachex.put(cache1, 1, 1) == {:ok, true}
    assert Cachex.put(cache1, 2, 2, expire: 5000) == {:ok, true}
    assert Cachex.put(cache2, 1, 1) == {:ok, true}
    assert Cachex.put(cache2, 2, 2, expire: 5000) == {:ok, true}

    # verify the hooks were updated with the message
    assert_receive {{:put, [1, 1, []]}, {:ok, true}}
    assert_receive {{:put, [1, 1, []]}, {:ok, true}}
    assert_receive {{:put, [2, 2, [expire: 5000]]}, {:ok, true}}
    assert_receive {{:put, [2, 2, [expire: 5000]]}, {:ok, true}}

    # read back all values from the cache
    assert Cachex.get(cache1, 1) == 1
    assert Cachex.get(cache1, 2) == 2
    assert Cachex.get(cache2, 1) == 1
    assert Cachex.get(cache2, 2) == 2

    # read back all key TTLs
    assert Cachex.ttl(cache1, 1) == nil

    # the second should have a TTL around 5s
    cache1
    |> Cachex.ttl!(2)
    |> assert_in_delta(5000, 10)

    # the second should have a TTL around 10s
    cache2
    |> Cachex.ttl!(1)
    |> assert_in_delta(10000, 10)

    # the fourth should have a TTL around 5s
    cache2
    |> Cachex.ttl!(2)
    |> assert_in_delta(5000, 10)
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "adding new entries to a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    assert Cachex.put(cache, 1, 1) == {:ok, true}
    assert Cachex.put(cache, 2, 2) == {:ok, true}

    # check the results of the calls across nodes
    assert Cachex.size(cache, local: true) == 1
    assert Cachex.size(cache, local: false) == 2
  end
end
