defmodule Cachex.Actions.PurgeTest do
  use Cachex.Test.Case

  # This test makes sure that we can manually purge expired records from the cache.
  # We attempt to purge before a key has expired and verify that it has not been
  # removed. We then wait until after the TTL has passed and ensure that it is
  # removed by the purge call. Finally we make sure to check the hook notifications.
  test "purging expired records in a cache" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = TestUtils.create_cache(hooks: [hook])

    # add a new cache entry
    {:ok, true} = Cachex.put(cache, "key", "value", ttl: 25)

    # flush messages
    TestUtils.flush()

    # purge before the entry expires
    purge1 = Cachex.purge(cache)

    # verify that the purge removed nothing
    assert(purge1 == {:ok, 0})

    # ensure we received a message
    assert_receive({{:purge, [[]]}, {:ok, 0}})

    # wait until the entry has expired
    :timer.sleep(50)

    # purge after the entry expires
    purge2 = Cachex.purge(cache)

    # verify that the purge removed the key
    assert(purge2 == {:ok, 1})

    # ensure we received a message
    assert_receive({{:purge, [[]]}, {:ok, 1}})

    # check whether the key exists
    exists = Cachex.exists?(cache, "key")

    # verify that the key is gone
    assert(exists == {:ok, false})
  end

  # This test verifies that the distributed router correctly controls
  # the purge/2 action in such a way that it can clean both a local
  # node as well as a remote node. We don't have to check functionality
  # of the entire action; just the actual routing of the action to the
  # target node(s) is of interest here.
  @tag distributed: true
  test "purging expired records in a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    {:ok, true} = Cachex.put(cache, 1, 1, ttl: 1)
    {:ok, true} = Cachex.put(cache, 2, 2, ttl: 1)

    # retrieve the cache size, should be 2
    {:ok, 2} = Cachex.size(cache)

    # give it a few ms to expire...
    :timer.sleep(5)

    # purge just the local cache to start with
    purge1 = Cachex.purge(cache, local: true)
    purge2 = Cachex.purge(cache, local: false)

    # check the local removed 1
    assert(purge1 == {:ok, 1})
    assert(purge2 == {:ok, 1})
  end
end
