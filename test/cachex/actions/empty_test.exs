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
    cache = Helper.create_cache(hooks: [hook])

    # check if the cache is empty
    result1 = Cachex.empty?(cache)

    # it should be
    assert(result1 == {:ok, true})

    # verify the hooks were updated with the message
    assert_receive({{:empty?, [[]]}, ^result1})

    # add some cache entries
    {:ok, true} = Cachex.put(cache, 1, 1)

    # check if the cache is empty
    result2 = Cachex.empty?(cache)

    # it shouldn't be
    assert(result2 == {:ok, false})

    # verify the hooks were updated with the message
    assert_receive({{:empty?, [[]]}, ^result2})
  end

  # This test verifies that the distributed router correctly controls
  # the empty?/2 action in such a way that it can clean both a local
  # node as well as a remote node. We don't have to check functionality
  # of the entire action; just the actual routing of the action to the
  # target node(s) is of interest here.
  @tag distributed: true
  test "checking if a cache cluster is empty" do
    # create a new cache cluster for cleaning
    {cache, _nodes} = Helper.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, true} = Cachex.put(cache, 2, 2)

    # check if the cache is empty, locally and remote
    empty1 = Cachex.empty?(cache, local: true)
    empty2 = Cachex.empty?(cache, local: false)

    # both should be non-empty
    assert(empty1 == {:ok, false})
    assert(empty2 == {:ok, false})

    # delete the key on the local node
    {:ok, 1} = Cachex.clear(cache, local: true)

    # check again as to whether the cache is empty
    empty3 = Cachex.empty?(cache, local: true)
    empty4 = Cachex.empty?(cache, local: false)

    # only the local node is now empty
    assert(empty3 == {:ok, true})
    assert(empty4 == {:ok, false})

    # finally delete all keys in the cluster
    {:ok, 1} = Cachex.clear(cache, local: false)

    # check again as to whether the cache is empty
    empty5 = Cachex.empty?(cache, local: true)
    empty6 = Cachex.empty?(cache, local: false)

    # both should now show empty
    assert(empty5 == {:ok, true})
    assert(empty6 == {:ok, true})
  end
end
