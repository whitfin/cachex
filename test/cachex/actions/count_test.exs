defmodule Cachex.Actions.CountTest do
  use Cachex.Test.Case

  # This test verifies that a cache can be successfully counted. Counting a cache
  # will return the size of the cache, but ignoring the number of expired entries.
  test "counting items in a cache" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = Helper.create_cache(hooks: [hook])

    # fill with some items
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, true} = Cachex.put(cache, 2, 2)
    {:ok, true} = Cachex.put(cache, 3, 3)

    # add some expired items
    {:ok, true} = Cachex.put(cache, 4, 4, ttl: 1)
    {:ok, true} = Cachex.put(cache, 5, 5, ttl: 1)
    {:ok, true} = Cachex.put(cache, 6, 6, ttl: 1)

    # let entries expire
    :timer.sleep(2)

    # clear all hook
    Helper.flush()

    # count the cache
    result = Cachex.count(cache)

    # only 3 items should come back
    assert(result == {:ok, 3})

    # verify the hooks were updated with the count
    assert_receive({{:count, [[]]}, ^result})
  end

  # This test verifies that the distributed router correctly controls
  # the count/2 action in such a way that it can count the records
  # in both a local node as well as a remote node. We don't have to
  # check functionality of the entire action; just the actual routing
  # of the action to the target node(s) is of interest here.
  @tag distributed: true
  test "counting items in a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes} = Helper.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, true} = Cachex.put(cache, 2, 2)

    # retrieve both the local and remote counts
    count1 = Cachex.count(cache, local: true)
    count2 = Cachex.count(cache, local: false)

    # check each node has 1
    assert(count1 == {:ok, 1})
    assert(count2 == {:ok, 2})
  end
end
