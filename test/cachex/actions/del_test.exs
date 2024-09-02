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
    {:ok, true} = Cachex.put(cache, 1, 1)

    # delete some entries
    result1 = Cachex.del(cache, 1)
    result2 = Cachex.del(cache, 2)

    # verify both are true
    assert(result1 == {:ok, true})
    assert(result2 == {:ok, true})

    # verify the hooks were updated with the delete
    assert_receive({{:del, [1, []]}, ^result1})
    assert_receive({{:del, [2, []]}, ^result2})

    # retrieve all items
    value1 = Cachex.get(cache, 1)
    value2 = Cachex.get(cache, 2)

    # verify the items are gone
    assert(value1 == {:ok, nil})
    assert(value2 == {:ok, nil})
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "removing entries from a cache cluster" do
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

    # delete each item from the cache cluster
    {:ok, true} = Cachex.del(cache, 1)
    {:ok, true} = Cachex.del(cache, 2)

    # check the results of the calls across nodes
    size3 = Cachex.size(cache, local: true)
    size4 = Cachex.size(cache, local: false)

    # no records are left
    assert(size3 == {:ok, 0})
    assert(size4 == {:ok, 0})
  end
end
