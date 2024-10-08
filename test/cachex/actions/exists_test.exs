defmodule Cachex.Actions.ExistsTest do
  use Cachex.Test.Case

  # This test verifies whether a key exists in a cache. If it does, we return
  # true. If not we return false. If the key has expired, we return false and
  # evict it on demand using the generic read action.
  test "checking if a key exists" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = TestUtils.create_cache(hooks: [hook])

    # add some keys to the cache
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, true} = Cachex.put(cache, 2, 2, expire: 1)

    # let TTLs clear
    :timer.sleep(2)

    # clear messages
    TestUtils.flush()

    # check if several keys exist
    exists1 = Cachex.exists?(cache, 1)
    exists2 = Cachex.exists?(cache, 2)
    exists3 = Cachex.exists?(cache, 3)

    # the first result should exist
    assert(exists1 == {:ok, true})

    # the next two should be missing
    assert(exists2 == {:ok, false})
    assert(exists3 == {:ok, false})

    # verify the hooks were updated with the message
    assert_receive({{:exists?, [1, []]}, ^exists1})
    assert_receive({{:exists?, [2, []]}, ^exists2})
    assert_receive({{:exists?, [3, []]}, ^exists3})

    # check we received valid purge actions for the TTL
    assert_receive({{:purge, [[]]}, {:ok, 1}})

    # retrieve all values from the cache
    value1 = Cachex.get(cache, 1)
    value2 = Cachex.get(cache, 2)
    value3 = Cachex.get(cache, 3)

    # verify the second was removed
    assert(value1 == {:ok, 1})
    assert(value2 == {:ok, nil})
    assert(value3 == {:ok, nil})
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "checking if a key exists in a cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, true} = Cachex.put(cache, 2, 2)

    # check the results of the calls across nodes
    exists1 = Cachex.exists?(cache, 1)
    exists2 = Cachex.exists?(cache, 2)

    # both exist in the cluster
    assert(exists1 == {:ok, true})
    assert(exists2 == {:ok, true})
  end
end
