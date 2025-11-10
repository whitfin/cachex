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
      TestUtils.create_cache(
        hooks: [hook],
        expiration: expiration(default: 10000)
      )

    # set some values in the cache
    assert Cachex.put_many(cache1, [{1, 1}, {2, 2}]) == :ok
    assert Cachex.put_many(cache1, [{3, 3}, {4, 4}], expire: 5000) == :ok
    assert Cachex.put_many(cache2, [{1, 1}, {2, 2}]) == :ok
    assert Cachex.put_many(cache2, [{3, 3}, {4, 4}], expire: 5000) == :ok

    # verify the hooks were updated with the message
    assert_receive {{:put_many, [[{1, 1}, {2, 2}], []]}, :ok}
    assert_receive {{:put_many, [[{1, 1}, {2, 2}], []]}, :ok}
    assert_receive {{:put_many, [[{3, 3}, {4, 4}], [expire: 5000]]}, :ok}
    assert_receive {{:put_many, [[{3, 3}, {4, 4}], [expire: 5000]]}, :ok}

    # read back all values from the cache
    assert Cachex.get(cache1, 1) == 1
    assert Cachex.get(cache1, 2) == 2
    assert Cachex.get(cache1, 3) == 3
    assert Cachex.get(cache1, 4) == 4
    assert Cachex.get(cache2, 1) == 1
    assert Cachex.get(cache2, 2) == 2
    assert Cachex.get(cache2, 3) == 3
    assert Cachex.get(cache2, 4) == 4

    # the first two should have no TTL
    assert Cachex.ttl(cache1, 1) == nil
    assert Cachex.ttl(cache1, 2) == nil

    # the second two should have a TTL around 5s
    assert_in_delta Cachex.ttl(cache1, 3), 5000, 10
    assert_in_delta Cachex.ttl(cache1, 4), 5000, 10

    # the third two should have a TTL around 10s
    assert_in_delta Cachex.ttl(cache2, 1), 10000, 10
    assert_in_delta Cachex.ttl(cache2, 2), 10000, 10

    # the last two should have a TTL around 5s
    assert_in_delta Cachex.ttl(cache2, 3), 5000, 10
    assert_in_delta Cachex.ttl(cache2, 4), 5000, 10
  end

  # This should no-op to avoid a crashing write, whilst
  # short circuiting in order to speed up the empty batch.
  test "handling empty pairs in a batch" do
    # create a test cache
    cache = TestUtils.create_cache()

    # try set some values in the cache
    assert Cachex.put_many(cache, []) == :ok
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
    assert Cachex.put_many(cache, [{1, 1}, "key"]) == error(:invalid_pairs)
    assert Cachex.put_many(cache, [{1, 1}, {2, 2, 2}]) == error(:invalid_pairs)

    # try without a list of pairs
    assert_raise FunctionClauseError, fn ->
      Cachex.put_many(cache, {1, 1})
    end
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "adding new entries to a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 2 & 3 hash to the same slots
    assert Cachex.put_many(cache, [{2, 2}, {3, 3}]) == :ok

    # try to retrieve both of the set keys
    assert Cachex.get(cache, 2) == 2
    assert Cachex.get(cache, 3) == 3
  end

  # This test verifies that all keys in a put_many/3 must hash to the
  # same slot in a cluster, otherwise a cross_slot error will occur.
  @tag distributed: true
  test "multiple slots will return a :cross_slot error" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 3 don't hash to the same slots, so there should be an error
    assert Cachex.put_many(cache, [{1, 1}, {3, 3}]) == {:error, :cross_slot}
  end
end
