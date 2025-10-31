defmodule Cachex.Actions.EmptyTest do
  use Cachex.Test.Case

  # This test verifies that a cache is empty. We first check that it is before
  # adding any items, and after we add some we check that it's no longer empty.
  # Hook messages are represented as size calls, as empty is purely sugar on top
  # of the size functionality.
  test "checking if a cache is empty" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = TestUtils.create_cache(hooks: [hook])

    # check if the cache is empty
    assert Cachex.empty?(cache)

    # verify the hooks were updated with the message
    assert_receive {{:empty?, [[]]}, true}

    # add some cache entries
    assert Cachex.put(cache, 1, 1)

    # check if the cache is empty
    refute Cachex.empty?(cache)

    # verify the hooks were updated with the message
    assert_receive {{:empty?, [[]]}, false}
  end

  # This test verifies that the distributed router correctly controls
  # the empty?/2 action in such a way that it can clean both a local
  # node as well as a remote node. We don't have to check functionality
  # of the entire action; just the actual routing of the action to the
  # target node(s) is of interest here.
  @tag distributed: true
  test "checking if a cache cluster is empty" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    assert Cachex.put(cache, 1, 1)
    assert Cachex.put(cache, 2, 2)

    # check if the cache is empty, locally and remote
    refute Cachex.empty?(cache, local: true)
    refute Cachex.empty?(cache, local: false)

    # delete the key on the local node
    assert Cachex.clear(cache, local: true) == 1

    # check again as to whether the cache is empty
    assert Cachex.empty?(cache, local: true)
    refute Cachex.empty?(cache, local: false)

    # finally delete all keys in the cluster
    assert Cachex.clear(cache, local: false) == 1

    # check again as to whether the cache is empty
    assert Cachex.empty?(cache, local: true)
    assert Cachex.empty?(cache, local: false)
  end
end
