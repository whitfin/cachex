defmodule Cachex.Actions.KeysTest do
  use Cachex.Test.Case

  # This test verifies that it's possible to retrieve the keys inside a cache.
  # It should be noted that the keys function takes TTL into account and only
  # returns the keys of those records which have not expired. Order is not in
  # any way guaranteed, even with no cache modification.
  test "retrieving the keys inside the cache" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = TestUtils.create_cache(hooks: [hook])

    # fill with some items
    assert Cachex.put(cache, 1, 1) == {:ok, true}
    assert Cachex.put(cache, 2, 2) == {:ok, true}
    assert Cachex.put(cache, 3, 3) == {:ok, true}

    # add some expired items
    assert Cachex.put(cache, 4, 4, expire: 1) == {:ok, true}
    assert Cachex.put(cache, 5, 5, expire: 1) == {:ok, true}
    assert Cachex.put(cache, 6, 6, expire: 1) == {:ok, true}

    # let entries expire
    :timer.sleep(2)

    # clear all hook
    TestUtils.flush()

    # retrieve the keys
    keys = Cachex.keys(cache)

    # only 3 items should come back
    assert Enum.sort(keys) == [1, 2, 3]

    # verify the hooks were updated with the count
    assert_receive {{:keys, [[]]}, ^keys}
  end

  # This test verifies that the distributed router correctly controls
  # the keys/2 action in such a way that it can clean both a local
  # node as well as a remote node. We don't have to check functionality
  # of the entire action; just the actual routing of the action to the
  # target node(s) is of interest here.
  @tag distributed: true
  test "checking if a cache cluster is empty" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    assert Cachex.put(cache, 1, 1) == {:ok, true}
    assert Cachex.put(cache, 2, 2) == {:ok, true}

    # retrieve the keys from both local & remote
    keys1 = Cachex.keys(cache, local: true)
    keys2 = Cachex.keys(cache, local: false)

    # local just one, cluster has two
    assert length(keys1) == 1
    assert length(keys2) == 2

    # delete the single local key
    assert Cachex.clear(cache, local: true) == 1

    # retrieve the keys again from both local & remote
    keys3 = Cachex.keys(cache, local: true)
    keys4 = Cachex.keys(cache, local: false)

    # now local has no keys
    assert length(keys3) == 0
    assert length(keys4) == 1

    # delete the remaining key inside the cluster
    assert Cachex.clear(cache, local: false) == 1

    # retrieve the keys again from both local & remote
    keys5 = Cachex.keys(cache, local: true)
    keys6 = Cachex.keys(cache, local: false)

    # now both don't have any keys
    assert length(keys5) == 0
    assert length(keys6) == 0
  end
end
