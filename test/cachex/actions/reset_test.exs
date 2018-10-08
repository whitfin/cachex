defmodule Cachex.Actions.ResetTest do
  use CachexCase

  # This test ensures that we can reset a cache completely, resetting the state
  # of all hooks and emptying the cache of keys. We verify this using the stats
  # hook and checking the creaionDate (which is set when the hook is started),
  # and ensuring that the creation_date resets when the cache does. We also verify
  # that the cache is empty after being reset. The second cache here with no hooks
  # is to ensure coverage of clearing a cache with no hooks, as there are optimizations
  # which avoid this from wasting time - this can sadly only be verified using
  # coverage tools, as the entire point is that it doesn't do anything.
  test "resetting a cache" do
    # create a test cache
    cache1 = Helper.create_cache([ stats: true ])

    # create a cache with no hooks
    cache2 = Helper.create_cache()

    # get current time
    ctime1 = now()

    # set some values
    { :ok, true } = Cachex.put(cache1, 1, 1)
    { :ok, true } = Cachex.put(cache2, 1, 1)

    # retrieve the stats
    stats1 = Cachex.stats!(cache1)

    # verify the stats
    assert_in_delta(stats1.meta.creation_date, ctime1, 10)

    # ensure the cache is not empty
    refute(Cachex."empty?!"(cache1))
    refute(Cachex."empty?!"(cache2))

    # wait for 10ms
    :timer.sleep(10)

    # get current time
    ctime2 = now()

    # reset the whole cache
    reset1 = Cachex.reset(cache1)
    reset2 = Cachex.reset(cache2)

    # verify the reset
    assert(reset1 == { :ok, true })
    assert(reset2 == { :ok, true })

    # ensure the cache is reset
    assert(Cachex."empty?!"(cache1))
    assert(Cachex."empty?!"(cache2))

    # retrieve the stats
    stats2 = Cachex.stats!(cache1)

    # verify they reset properly
    assert_in_delta(stats2.meta.creation_date, ctime2, 10)
  end

  # This test ensures that we can reset a cache without touching any of the hooks
  # and only emptying the cache. We verify this using the stats hook and checking
  # the creaionDate does not change after the cache has been reset. We make sure
  # to verify that the cache is empty after the reset.
  test "resetting only a cache" do
    # create a test cache
    cache = Helper.create_cache([ stats: true ])

    # get current time
    ctime1 = now()

    # set some values
    { :ok, true } = Cachex.put(cache, 1, 1)

    # retrieve the stats
    stats1 = Cachex.stats!(cache)

    # verify the stats
    assert_in_delta(stats1.meta.creation_date, ctime1, 5)

    # ensure the cache is not empty
    refute(Cachex."empty?!"(cache))

    # reset only cache
    reset1 = Cachex.reset(cache, [ only: :cache ])

    # verify the reset
    assert(reset1 == { :ok, true })

    # ensure the cache is reset
    assert(Cachex."empty?!"(cache))

    # retrieve the stats
    stats2 = Cachex.stats!(cache)

    # verify they didn't change
    assert(stats2.meta.creation_date == stats1.meta.creation_date)
  end

  # This test covers the resetting of a cache's hooks, but not resetting the cache
  # itself. We do this by ensuring that the cache never becomes empty, but the
  # creation_date on the stats hook is reset. Firstly we do a reset with a whitelist
  # of hooks to reset to ensure that this does not reset the stats hook (thus
  # verifying that this works correctly), and then we reset all hooks and check
  # that the creation_date of the stats hook is reset properly.
  test "resetting only a cache's hooks" do
    # create a test cache
    cache = Helper.create_cache([ stats: true ])

    # get current time
    ctime1 = now()

    # set some values
    { :ok, true } = Cachex.put(cache, 1, 1)

    # retrieve the stats
    stats1 = Cachex.stats!(cache)

    # verify the stats
    assert_in_delta(stats1.meta.creation_date, ctime1, 5)

    # ensure the cache is not empty
    refute(Cachex."empty?!"(cache))

    # wait for 10ms
    :timer.sleep(10)

    # get current time
    ctime2 = now()

    # reset only cache
    reset1 = Cachex.reset(cache, [ only: :hooks, hooks: [ MyModule ] ])

    # verify the reset
    assert(reset1 == { :ok, true })

    # ensure the cache is not reset
    refute(Cachex."empty?!"(cache))

    # retrieve the stats
    stats2 = Cachex.stats!(cache)

    # verify they don't reset
    assert(stats2.meta.creation_date == stats1.meta.creation_date)

    # reset without a hooks list
    reset2 = Cachex.reset(cache, [ only: :hooks ])

    # verify the reset
    assert(reset2 == { :ok, true })

    # ensure the cache is not reset
    refute(Cachex."empty?!"(cache))

    # retrieve the stats
    stats3 = Cachex.stats!(cache)

    # verify they don't reset
    assert_in_delta(stats3.meta.creation_date, ctime2, 5)
  end

  # This test verifies that the distributed router correctly controls
  # the reset/2 action in such a way that it can clean both a local
  # node as well as a remote node. We don't have to check functionality
  # of the entire action; just the actual routing of the action to the
  # target node(s) is of interest here.
  @tag distributed: true
  test "resetting a cache cluster" do
    # create a new cache cluster for cleaning
    { cache, _nodes } = Helper.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    { :ok, true } = Cachex.put(cache, 1, 1)
    { :ok, true } = Cachex.put(cache, 2, 2)

    # retrieve the cache size, should be 2
    { :ok, 2 } = Cachex.size(cache)

    # reset just the local cache to start with
    reset1 = Cachex.reset(cache, [ local: true ])
    sized1 = Cachex.size(cache)

    # check the local removal worked
    assert(reset1 == { :ok, true })
    assert(sized1 == { :ok, 1 })

    # reset the rest of the cluster cached
    reset2 = Cachex.reset(cache, [ local: false ])
    sized2 = Cachex.size(cache)

    # check the other removals worked
    assert(reset2 == { :ok, true })
    assert(sized2 == { :ok, 0 })
  end
end
