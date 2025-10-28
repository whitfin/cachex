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
    assert Cachex.put(cache, 1, 1) == {:ok, true}
    assert Cachex.put(cache, 2, 2, expire: 1) == {:ok, true}

    # let TTLs clear
    :timer.sleep(2)

    # clear messages
    TestUtils.flush()

    # check if several keys exist
    assert Cachex.exists?(cache, 1)
    refute Cachex.exists?(cache, 2)
    refute Cachex.exists?(cache, 3)

    # verify the hooks were updated with the message
    assert_receive({{:exists?, [1, []]}, true})
    assert_receive({{:exists?, [2, []]}, false})
    assert_receive({{:exists?, [3, []]}, false})

    # check we received valid purge actions for the TTL
    assert_receive({{:purge, [[]]}, {:ok, 1}})

    # retrieve all values from the cache
    assert Cachex.get(cache, 1) == {:ok, 1}
    assert Cachex.get(cache, 2) == {:ok, nil}
    assert Cachex.get(cache, 3) == {:ok, nil}
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "checking if a key exists in a cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    assert Cachex.put(cache, 1, 1) == {:ok, true}
    assert Cachex.put(cache, 2, 2) == {:ok, true}

    # check the results of the calls across nodes
    assert Cachex.exists?(cache, 1)
    assert Cachex.exists?(cache, 2)
  end
end
