defmodule Cachex.Actions.ClearTest do
  use Cachex.Test.Case

  # This test verifies that a cache can be successfully cleared. We fill the cache
  # and clear it, verifying that the entries were removed successfully. We also
  # ensure that hooks were updated with the correct values.
  test "clearing a cache of all items" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = TestUtils.create_cache(hooks: [hook])

    # fill with some items
    assert Cachex.put(cache, 1, 1)
    assert Cachex.put(cache, 2, 2)
    assert Cachex.put(cache, 3, 3)

    # clear all hook
    TestUtils.flush()

    # 3 items should have been removed
    assert Cachex.clear(cache) == 3

    # verify the hooks were updated with the clear
    assert_receive {{:clear, [[]]}, 3}

    # verify the size call never notified
    refute_receive {{:size, [[]]}, 3}

    # retrieve all items, verify the items are gone
    assert Cachex.get(cache, 1) == nil
    assert Cachex.get(cache, 2) == nil
    assert Cachex.get(cache, 3) == nil
  end

  # This test verifies that the distributed router correctly controls
  # the clear/2 action in such a way that it can clean both a local
  # node as well as a remote node. We don't have to check functionality
  # of the entire action; just the actual routing of the action to the
  # target node(s) is of interest here.
  @tag distributed: true
  test "clearing a cache cluster of all items" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    assert Cachex.put(cache, 1, 1)
    assert Cachex.put(cache, 2, 2)

    # retrieve the cache size, should be 2
    assert Cachex.size(cache) == 2

    # clear just the local cache to start with
    assert Cachex.clear(cache, local: true) == 1
    assert Cachex.clear(cache, local: false) == 1
  end
end
