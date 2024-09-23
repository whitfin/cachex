defmodule Cachex.Actions.SizeTest do
  use Cachex.Test.Case

  # This test verifies the size of a cache, by checking both with
  # and without expired records. This is controlled by `:expired`.
  test "checking the total size of a cache" do
    # create a test cache
    cache = TestUtils.create_cache()

    # retrieve the cache size
    result1 = Cachex.size(cache)

    # it should be empty
    assert(result1 == {:ok, 0})

    # add some cache entries
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, true} = Cachex.put(cache, 2, 2, expire: 1)

    # wait 2 ms to expire
    :timer.sleep(2)

    # retrieve the cache size
    result2 = Cachex.size(cache)
    result3 = Cachex.size(cache, expired: false)

    # it should show the new key
    assert(result2 == {:ok, 2})
    assert(result3 == {:ok, 1})
  end

  # This test verifies that the distributed router correctly controls
  # the size/2 action in such a way that it can clean both a local
  # node as well as a remote node. We don't have to check functionality
  # of the entire action; just the actual routing of the action to the
  # target node(s) is of interest here.
  @tag distributed: true
  test "checking the total size of a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, true} = Cachex.put(cache, 2, 2)

    # retrieve the cache size, should be 2
    size1 = Cachex.size(cache)

    # check the size of the cache
    assert(size1 == {:ok, 2})

    # clear just the local cache to start with
    {:ok, 1} = Cachex.clear(cache, local: true)

    # fetch the size of local and remote
    size2 = Cachex.size(cache, local: true)
    size3 = Cachex.size(cache, local: false)

    # check that the local is 0, remote is 1
    assert(size2 == {:ok, 0})
    assert(size3 == {:ok, 1})

    # clear the entire cluster at this point
    {:ok, 1} = Cachex.clear(cache)

    # fetch the size of local and remote (again)
    size4 = Cachex.size(cache, local: true)
    size5 = Cachex.size(cache, local: false)

    # check that both are now 0
    assert(size4 == {:ok, 0})
    assert(size5 == {:ok, 0})
  end
end
