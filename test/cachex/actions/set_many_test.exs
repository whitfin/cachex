defmodule Cachex.Actions.SetManyTest do
  use CachexCase

  # This test just covers the case of forwarding calls
  # to set_many() through to put_many() in order to
  # validate the backwards compatibility calls.
  test "forwarding calls to put_many(2/3)" do
    # create a test cache
    cache = Helper.create_cache()

    # set values in the cache
    result1 = Cachex.set_many(cache, [{1, 1}, {2, 2}])
    result2 = Cachex.set_many(cache, [{3, 3}, {4, 4}], ttl: 5000)

    # verify the results of the writes
    assert(result1 == {:ok, true})
    assert(result2 == {:ok, true})

    # retrieve the written value
    result2 = Cachex.get(cache, 1)
    result3 = Cachex.get(cache, 2)
    result4 = Cachex.get(cache, 3)
    result5 = Cachex.get(cache, 4)

    # check that it was written
    assert(result2 == {:ok, 1})
    assert(result3 == {:ok, 2})
    assert(result4 == {:ok, 3})
    assert(result5 == {:ok, 4})

    # check the ttl on the last calls
    result6 = Cachex.ttl!(cache, 3)
    result7 = Cachex.ttl!(cache, 4)

    # the second should have a TTL around 5s
    assert_in_delta(result6, 5000, 10)
    assert_in_delta(result7, 5000, 10)
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "adding new entries to a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes} = Helper.create_cache_cluster(2)

    # we know that 2 & 3 hash to the same slots
    {:ok, true} = Cachex.set_many(cache, [{2, 2}, {3, 3}])

    # try to retrieve both of the set keys
    get1 = Cachex.get(cache, 2)
    get2 = Cachex.get(cache, 3)

    # both should come back
    assert(get1 == {:ok, 2})
    assert(get2 == {:ok, 3})
  end

  # This test verifies that all keys in a set_many/3 must hash to the
  # same slot in a cluster, otherwise a cross_slot error will occur.
  @tag distributed: true
  test "multiple slots will return a :cross_slot error" do
    # create a new cache cluster for cleaning
    {cache, _nodes} = Helper.create_cache_cluster(2)

    # we know that 1 & 3 don't hash to the same slots
    set_many = Cachex.set_many(cache, [{1, 1}, {3, 3}])

    # so there should be an error
    assert(set_many == {:error, :cross_slot})
  end
end
