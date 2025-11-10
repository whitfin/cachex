defmodule Cachex.Actions.SizeTest do
  use Cachex.Test.Case

  # This test verifies the size of a cache, by checking both with
  # and without expired records. This is controlled by `:expired`.
  test "checking the total size of a cache" do
    # create a test cache
    cache = TestUtils.create_cache()

    # retrieve the cache size, it should be empty
    assert Cachex.size(cache) == 0

    # add some cache entries
    assert Cachex.put(cache, 1, 1) == :ok
    assert Cachex.put(cache, 2, 2, expire: 1) == :ok

    # wait 2 ms to expire
    :timer.sleep(2)

    # retrieve the cache size
    assert Cachex.size(cache) == 2
    assert Cachex.size(cache, expired: false) == 1
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
    assert Cachex.put(cache, 1, 1) == :ok
    assert Cachex.put(cache, 2, 2) == :ok

    # retrieve the cache size, should be 2
    assert Cachex.size(cache) == 2

    # clear just the local cache to start with
    assert Cachex.clear(cache, local: true) == 1

    # fetch the size of local and remote
    assert Cachex.size(cache, local: true) == 0
    assert Cachex.size(cache, local: false) == 1

    # clear the entire cluster at this point
    assert Cachex.clear(cache) == 1

    # fetch the size of local and remote (again)
    assert Cachex.size(cache, local: true) == 0
    assert Cachex.size(cache, local: false) == 0
  end
end
