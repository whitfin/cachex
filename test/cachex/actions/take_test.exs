defmodule Cachex.Actions.TakeTest do
  use Cachex.Test.Case

  # This test verifies that we can take keys from the cache. If a key has expired,
  # the value is not returned and the hooks are updated with an eviction. If the
  # key is missing, we return a message stating as such.
  test "taking keys from a cache" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = TestUtils.create_cache(hooks: [hook])

    # set some keys in the cache
    assert Cachex.put(cache, 1, 1) == :ok
    assert Cachex.put(cache, 2, 2, expire: 1) == :ok

    # wait for the TTL to pass
    :timer.sleep(2)

    # flush all existing messages
    TestUtils.flush()

    # take the first and second key
    assert Cachex.take(cache, 1) == 1
    assert Cachex.take(cache, 2) == nil

    # take a missing key
    assert Cachex.take(cache, 3) == nil

    # assert we receive valid notifications
    assert_receive {{:take, [1, []]}, 1}
    assert_receive {{:take, [2, []]}, nil}
    assert_receive {{:take, [3, []]}, nil}

    # check we received valid purge actions for the TTL
    assert_receive {{:purge, [[]]}, 1}

    # ensure that the keys no longer exist in the cache
    refute Cachex.exists?(cache, 1)
    refute Cachex.exists?(cache, 2)
    refute Cachex.exists?(cache, 3)
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "taking entries from a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    assert Cachex.put(cache, 1, 1) == :ok
    assert Cachex.put(cache, 2, 2) == :ok

    # check the results of the calls across nodes
    assert Cachex.size(cache, local: true) == 1
    assert Cachex.size(cache, local: false) == 2

    # take each item from the cache cluster
    assert Cachex.take(cache, 1) == 1
    assert Cachex.take(cache, 2) == 2

    # check the results of the calls across nodes
    assert Cachex.size(cache, local: true) == 0
    assert Cachex.size(cache, local: false) == 0
  end
end
