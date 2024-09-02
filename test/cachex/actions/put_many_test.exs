defmodule Cachex.Actions.PutManyTest do
  use Cachex.Test.Case

  # This test verifies the addition of many new entries to a cache. It will
  # ensure that values can be added and can be expired as necessary. These
  # test cases operate in the same way as the `set()` tests, just using the
  # batch insertion method for a cache instead of the default insert.
  test "adding many new values to the cache" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache1 = TestUtils.create_cache(hooks: [hook])

    # create a test cache with a default ttl
    cache2 =
      TestUtils.create_cache(hooks: [hook], expiration: expiration(default: 10000))

    # set some values in the cache
    set1 = Cachex.put_many(cache1, [{1, 1}, {2, 2}])
    set2 = Cachex.put_many(cache1, [{3, 3}, {4, 4}], ttl: 5000)
    set3 = Cachex.put_many(cache2, [{1, 1}, {2, 2}])
    set4 = Cachex.put_many(cache2, [{3, 3}, {4, 4}], ttl: 5000)

    # ensure all set actions worked
    assert(set1 == {:ok, true})
    assert(set2 == {:ok, true})
    assert(set3 == {:ok, true})
    assert(set4 == {:ok, true})

    # verify the hooks were updated with the message
    assert_receive({{:put_many, [[{1, 1}, {2, 2}], []]}, ^set1})
    assert_receive({{:put_many, [[{1, 1}, {2, 2}], []]}, ^set3})
    assert_receive({{:put_many, [[{3, 3}, {4, 4}], [ttl: 5000]]}, ^set2})
    assert_receive({{:put_many, [[{3, 3}, {4, 4}], [ttl: 5000]]}, ^set4})

    # read back all values from the cache
    value1 = Cachex.get(cache1, 1)
    value2 = Cachex.get(cache1, 2)
    value3 = Cachex.get(cache1, 3)
    value4 = Cachex.get(cache1, 4)
    value5 = Cachex.get(cache2, 1)
    value6 = Cachex.get(cache2, 2)
    value7 = Cachex.get(cache2, 3)
    value8 = Cachex.get(cache2, 4)

    # verify all values exist
    assert(value1 == {:ok, 1})
    assert(value2 == {:ok, 2})
    assert(value3 == {:ok, 3})
    assert(value4 == {:ok, 4})
    assert(value5 == {:ok, 1})
    assert(value6 == {:ok, 2})
    assert(value7 == {:ok, 3})
    assert(value8 == {:ok, 4})

    # read back all key TTLs
    ttl1 = Cachex.ttl!(cache1, 1)
    ttl2 = Cachex.ttl!(cache1, 2)
    ttl3 = Cachex.ttl!(cache1, 3)
    ttl4 = Cachex.ttl!(cache1, 4)
    ttl5 = Cachex.ttl!(cache2, 1)
    ttl6 = Cachex.ttl!(cache2, 2)
    ttl7 = Cachex.ttl!(cache2, 3)
    ttl8 = Cachex.ttl!(cache2, 4)

    # the first two should have no TTL
    assert(ttl1 == nil)
    assert(ttl2 == nil)

    # the second two should have a TTL around 5s
    assert_in_delta(ttl3, 5000, 10)
    assert_in_delta(ttl4, 5000, 10)

    # the third two should have a TTL around 10s
    assert_in_delta(ttl5, 10000, 10)
    assert_in_delta(ttl6, 10000, 10)

    # the last two should have a TTL around 5s
    assert_in_delta(ttl7, 5000, 10)
    assert_in_delta(ttl8, 5000, 10)
  end

  # This should no-op to avoid a crashing write, whilst
  # short circuiting in order to speed up the empty batch.
  test "handling empty pairs in a batch" do
    # create a test cache
    cache = TestUtils.create_cache()

    # try set some values in the cache
    result = Cachex.put_many(cache, [])

    # should work, but no writes
    assert(result == {:ok, false})
  end

  # Since we have a hard requirement on the format of a batch, we
  # need a quick test to ensure that everything is rejected as
  # necessary if they do not match the correct pair format.
  test "handling invalid pairs in a batch" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = TestUtils.create_cache(hooks: [hook])

    # try set some values in the cache
    set1 = Cachex.put_many(cache, [{1, 1}, "key"])
    set2 = Cachex.put_many(cache, [{1, 1}, {2, 2, 2}])

    # ensure all set actions failed
    assert(set1 == error(:invalid_pairs))
    assert(set2 == error(:invalid_pairs))

    # try without a list of pairs
    assert_raise(FunctionClauseError, fn ->
      Cachex.put_many(cache, {1, 1})
    end)
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "adding new entries to a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 2 & 3 hash to the same slots
    {:ok, true} = Cachex.put_many(cache, [{2, 2}, {3, 3}])

    # try to retrieve both of the set keys
    get1 = Cachex.get(cache, 2)
    get2 = Cachex.get(cache, 3)

    # both should come back
    assert(get1 == {:ok, 2})
    assert(get2 == {:ok, 3})
  end

  # This test verifies that all keys in a put_many/3 must hash to the
  # same slot in a cluster, otherwise a cross_slot error will occur.
  @tag distributed: true
  test "multiple slots will return a :cross_slot error" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 3 don't hash to the same slots
    put_many = Cachex.put_many(cache, [{1, 1}, {3, 3}])

    # so there should be an error
    assert(put_many == {:error, :cross_slot})
  end
end
