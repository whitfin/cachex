defmodule Cachex.Actions.SizeTest do
  use Cachex.Test.Case

  # This test verifies the size of a cache. It should be noted that size is the
  # total size of the cache, regardless of any evictions (unlike count). We make
  # sure that evictions aren't taken into account, and that size increments as
  # new keys are added to the cache.
  test "checking the total size of a cache" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = Helper.create_cache(hooks: [hook])

    # retrieve the cache size
    result1 = Cachex.size(cache)

    # it should be empty
    assert(result1 == {:ok, 0})

    # verify the hooks were updated with the message
    assert_receive({{:size, [[]]}, ^result1})

    # add some cache entries
    {:ok, true} = Cachex.put(cache, 1, 1)

    # retrieve the cache size
    result2 = Cachex.size(cache)

    # it should show the new key
    assert(result2 == {:ok, 1})

    # verify the hooks were updated with the message
    assert_receive({{:size, [[]]}, ^result2})

    # add a final entry
    {:ok, true} = Cachex.put(cache, 2, 2, ttl: 1)

    # let it expire
    :timer.sleep(2)

    # retrieve the cache size
    result3 = Cachex.size(cache)

    # it shouldn't care about TTL
    assert(result3 == {:ok, 2})

    # verify the hooks were updated with the message
    assert_receive({{:size, [[]]}, ^result3})
  end

  # This test verifies that the distributed router correctly controls
  # the size/2 action in such a way that it can clean both a local
  # node as well as a remote node. We don't have to check functionality
  # of the entire action; just the actual routing of the action to the
  # target node(s) is of interest here.
  @tag distributed: true
  test "checking the total size of a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes} = Helper.create_cache_cluster(2)

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
