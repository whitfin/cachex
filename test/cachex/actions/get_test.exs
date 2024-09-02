defmodule Cachex.Actions.GetTest do
  use Cachex.Test.Case

  # This test verifies that we can retrieve keys from the cache.
  # If a key has expired, the value is not returned and the hooks
  # are updated with an eviction. If the key is missing, we return
  # a message stating as such.
  test "retrieving keys from a cache" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache1 = TestUtils.create_cache(hooks: [hook])

    # set some keys in the cache
    {:ok, true} = Cachex.put(cache1, 1, 1)
    {:ok, true} = Cachex.put(cache1, 2, 2, ttl: 1)

    # wait for the TTL to pass
    :timer.sleep(2)

    # flush all existing messages
    TestUtils.flush()

    # take the first and second key
    result1 = Cachex.get(cache1, 1)
    result2 = Cachex.get(cache1, 2)

    # take a missing key with no fallback
    result3 = Cachex.get(cache1, 3)

    # verify the first key is retrieved
    assert(result1 == {:ok, 1})

    # verify the second and third keys are missing
    assert(result2 == {:ok, nil})
    assert(result3 == {:ok, nil})

    # assert we receive valid notifications
    assert_receive({{:get, [1, []]}, ^result1})
    assert_receive({{:get, [2, []]}, ^result2})
    assert_receive({{:get, [3, []]}, ^result3})

    # check we received valid purge actions for the TTL
    assert_receive({{:purge, [[]]}, {:ok, 1}})
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "retrieving keys from a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, true} = Cachex.put(cache, 2, 2)

    # try to retrieve both of the set keys
    get1 = Cachex.get(cache, 1)
    get2 = Cachex.get(cache, 2)

    # both should come back
    assert(get1 == {:ok, 1})
    assert(get2 == {:ok, 2})
  end
end
