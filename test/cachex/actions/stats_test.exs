defmodule Cachex.Actions.StatsTest do
  use CachexCase

  # This test covers stats retrieval by making sure that the numbers coming back
  # are both accurate and concise. We verify that the payload returned can be
  # filtered by the provided flags in order to customize output correctly.
  test "retrieving stats for a cache" do
    # create a test cache
    cache = Helper.create_cache(stats: true)

    # retrieve current time
    ctime = now()

    # execute some cache actions
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, 1} = Cachex.get(cache, 1)

    # retrieve default stats
    stats = Cachex.stats!(cache)

    # verify the first returns a valid meta object
    assert_in_delta(stats.meta.creation_date, ctime, 5)

    # verify attached statistics
    assert(stats.hits == 1)
    assert(stats.misses == 0)
    assert(stats.operations == 2)
    assert(stats.writes == 1)

    # verify attached rates
    assert(stats.hit_rate == 100)
  end

  # This test just verifies that we receive an error trying to retrieve stats
  # when they have already been disabled.
  test "retrieving stats from a disabled cache" do
    # create a test cache
    cache = Helper.create_cache(stats: false)

    # retrieve default stats
    stats = Cachex.stats(cache)

    # we should receive an error
    assert(stats == {:error, :stats_disabled})
  end

  # This test verifies that we correctly handle hit/miss rates when there are 0
  # values, to avoid arithmetic errors. We very 100% hit/miss rates, as well as
  # 50% either way.
  test "retrieving different rate combinations" do
    # create test caches
    cache1 = Helper.create_cache(stats: true)
    cache2 = Helper.create_cache(stats: true)
    cache3 = Helper.create_cache(stats: true)
    cache4 = Helper.create_cache(stats: true)

    # set cache1 to 100% misses
    {:ok, nil} = Cachex.get(cache1, 1)

    # set cache2 to 100% hits
    {:ok, true} = Cachex.put(cache2, 1, 1)
    {:ok, 1} = Cachex.get(cache2, 1)

    # set cache3 to be 50% each way
    {:ok, true} = Cachex.put(cache3, 1, 1)
    {:ok, 1} = Cachex.get(cache3, 1)
    {:ok, nil} = Cachex.get(cache3, 2)

    # set cache4 to have some loads
    {:commit, 1} = Cachex.fetch(cache4, 1, & &1)

    # retrieve all cache rates
    stats1 = Cachex.stats!(cache1)
    stats2 = Cachex.stats!(cache2)
    stats3 = Cachex.stats!(cache3)
    stats4 = Cachex.stats!(cache4)

    # remove the metadata from the stats
    stats1 = Map.delete(stats1, :meta)
    stats2 = Map.delete(stats2, :meta)
    stats3 = Map.delete(stats3, :meta)
    stats4 = Map.delete(stats4, :meta)

    # verify a 100% miss rate for cache1
    assert(
      stats1 == %{
        hits: 0,
        hit_rate: 0.0,
        misses: 1,
        miss_rate: 100.0,
        operations: 1,
        calls: %{
          get: 1
        }
      }
    )

    # verify a 100% hit rate for cache2
    assert(
      stats2 == %{
        hits: 1,
        hit_rate: 100.0,
        misses: 0,
        miss_rate: 0.0,
        operations: 2,
        writes: 1,
        calls: %{
          get: 1,
          put: 1
        }
      }
    )

    # verify a 50% hit rate for cache3
    assert(
      stats3 == %{
        hits: 1,
        hit_rate: 50.0,
        misses: 1,
        miss_rate: 50.0,
        operations: 3,
        writes: 1,
        calls: %{
          get: 2,
          put: 1
        }
      }
    )

    # verify a load count for cache4
    assert(
      stats4 == %{
        hits: 0,
        hit_rate: 0.0,
        fetches: 1,
        misses: 1,
        miss_rate: 100.0,
        operations: 1,
        writes: 1,
        calls: %{
          fetch: 1
        }
      }
    )
  end

  # This test verifies that the distributed router correctly controls
  # the stats/2 action in such a way that it can clean both a local
  # node as well as a remote node. We don't have to check functionality
  # of the entire action; just the actual routing of the action to the
  # target node(s) is of interest here.
  @tag distributed: true
  test "retrieving stats for a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes} = Helper.create_cache_cluster(2, stats: true)

    # we know that 1 & 2 hash to different nodes
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, true} = Cachex.put(cache, 2, 2)

    # generate a hit rate to check that
    {:ok, 1} = Cachex.get(cache, 1)
    {:ok, nil} = Cachex.get(cache, 3)

    # retrieve the stats from both local & remote
    {:ok, stats1} = Cachex.stats(cache, local: true)
    {:ok, stats2} = Cachex.stats(cache, local: false)

    # check 2 local, 5 global
    assert(stats1.calls.put == 1)
    assert(stats1.operations == 2)

    assert(
      stats1.hit_rate == 100.0 ||
        stats1.miss_rate == 100.0
    )

    assert(stats2.calls.put == 2)
    assert(stats2.operations == 5)
    assert(stats2.hit_rate == 50.0)
  end
end
