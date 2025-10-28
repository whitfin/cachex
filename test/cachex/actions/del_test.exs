defmodule Cachex.Actions.DelTest do
  use Cachex.Test.Case

  # This case tests that we can safely remove items from the cache. We test the
  # removal of both existing and missing keys, as the behaviour is the same for
  # both. We also ensure that hooks receive the delete notification successfully.
  test "removing entries from a cache" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = TestUtils.create_cache(hooks: [hook])

    # add some cache entries
    assert Cachex.put(cache, 1, 1) == {:ok, true}

    # delete some entries, verify both are true
    assert Cachex.del(cache, 1) == {:ok, true}
    assert Cachex.del(cache, 2) == {:ok, true}

    # verify the hooks were updated with the delete
    assert_receive({{:del, [1, []]}, {:ok, true}})
    assert_receive({{:del, [2, []]}, {:ok, true}})

    # retrieve all items, verify the items are gone
    assert Cachex.get(cache, 1) == {:ok, nil}
    assert Cachex.get(cache, 2) == {:ok, nil}
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "removing entries from a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    assert Cachex.put(cache, 1, 1) == {:ok, true}
    assert Cachex.put(cache, 2, 2) == {:ok, true}

    # check the results of the calls across nodes
    assert Cachex.size(cache, local: true) == 1
    assert Cachex.size(cache, local: false) == 2

    # delete each item from the cache cluster
    assert Cachex.del(cache, 1) == {:ok, true}
    assert Cachex.del(cache, 2) == {:ok, true}

    # check the results of the calls across nodes
    assert Cachex.size(cache, local: true) == 0
    assert Cachex.size(cache, local: false) == 0
  end
end
