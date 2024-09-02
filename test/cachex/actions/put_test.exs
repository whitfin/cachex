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
      TestUtils.create_cache(hooks: [hook], expiration: expiration(default: 10000))

    # set some values in the cache
    set1 = Cachex.put(cache1, 1, 1)
    set2 = Cachex.put(cache1, 2, 2, ttl: 5000)
    set3 = Cachex.put(cache2, 1, 1)
    set4 = Cachex.put(cache2, 2, 2, ttl: 5000)

    # ensure all set actions worked
    assert(set1 == {:ok, true})
    assert(set2 == {:ok, true})
    assert(set3 == {:ok, true})
    assert(set4 == {:ok, true})

    # verify the hooks were updated with the message
    assert_receive({{:put, [1, 1, []]}, ^set1})
    assert_receive({{:put, [1, 1, []]}, ^set3})
    assert_receive({{:put, [2, 2, [ttl: 5000]]}, ^set2})
    assert_receive({{:put, [2, 2, [ttl: 5000]]}, ^set4})

    # read back all values from the cache
    value1 = Cachex.get(cache1, 1)
    value2 = Cachex.get(cache1, 2)
    value3 = Cachex.get(cache2, 1)
    value4 = Cachex.get(cache2, 2)

    # verify all values exist
    assert(value1 == {:ok, 1})
    assert(value2 == {:ok, 2})
    assert(value3 == {:ok, 1})
    assert(value4 == {:ok, 2})

    # read back all key TTLs
    ttl1 = Cachex.ttl!(cache1, 1)
    ttl2 = Cachex.ttl!(cache1, 2)
    ttl3 = Cachex.ttl!(cache2, 1)
    ttl4 = Cachex.ttl!(cache2, 2)

    # the first should have no TTL
    assert(ttl1 == nil)

    # the second should have a TTL around 5s
    assert_in_delta(ttl2, 5000, 10)

    # the second should have a TTL around 10s
    assert_in_delta(ttl3, 10000, 10)

    # the fourth should have a TTL around 5s
    assert_in_delta(ttl4, 5000, 10)
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "adding new entries to a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, true} = Cachex.put(cache, 2, 2)

    # check the results of the calls across nodes
    size1 = Cachex.size(cache, local: true)
    size2 = Cachex.size(cache, local: false)

    # one local, two total
    assert(size1 == {:ok, 1})
    assert(size2 == {:ok, 2})
  end
end
