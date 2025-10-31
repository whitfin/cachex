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
    assert Cachex.put(cache, "key", "value", expire: 25)

    # flush messages
    TestUtils.flush()

    # purge before the entry expires
    assert Cachex.purge(cache) == 0

    # ensure we received a message
    assert_receive {{:purge, [[]]}, 0}

    # wait until the entry has expired
    :timer.sleep(50)

    # purge after the entry expires
    assert Cachex.purge(cache) == 1

    # ensure we received a message
    assert_receive {{:purge, [[]]}, 1}

    # check whether the key exists, verify that the key is gone
    refute Cachex.exists?(cache, "key")
  end

  # This test verifies that the distributed router correctly controls
  # the purge/2 action in such a way that it can clean both a local
  # node as well as a remote node. We don't have to check functionality
  # of the entire action; just the actual routing of the action to the
  # target node(s) is of interest here.
  @tag distributed: true
  test "purging expired records in a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    assert Cachex.put(cache, 1, 1, expire: 1)
    assert Cachex.put(cache, 2, 2, expire: 1)

    # retrieve the cache size, should be 2
    assert Cachex.size(cache) == 2

    # give it a few ms to expire...
    :timer.sleep(5)

    # purge just the local cache to start with
    assert Cachex.purge(cache, local: true) == 1
    assert Cachex.purge(cache, local: false) == 1
  end
end
