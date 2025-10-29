defmodule Cachex.Actions.StatsTest do
  use Cachex.Test.Case

  # This test covers stats retrieval by making sure that the numbers coming back
  # are both accurate and concise. We verify that the payload returned can be
  # filtered by the provided flags in order to customize output correctly.
  test "retrieving stats for a cache" do
    # create a test cache
    cache =
      TestUtils.create_cache(
        hooks: [
          hook(module: Cachex.Stats)
        ]
      )

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
    assert stats.hits == 1
    assert stats.misses == 0
    assert stats.operations == 2
    assert stats.writes == 1

    # verify attached rates
    assert stats.hit_rate == 100
  end

  # This test just verifies that we receive an error trying to retrieve stats
  # when they have already been disabled.
  test "retrieving stats from a disabled cache" do
    # create a test cache
    cache = TestUtils.create_cache(stats: false)

    # retrieve default stats, we should receive an error
    assert Cachex.stats(cache) == {:error, :stats_disabled}
  end

  # This test verifies that we correctly handle hit/miss rates when there are 0
  # values, to avoid arithmetic errors. We very 100% hit/miss rates, as well as
  # 50% either way.
  test "retrieving different rate combinations" do
    # create a stats hook
    hook = hook(module: Cachex.Stats)

    # create test caches
    cache1 = TestUtils.create_cache(hooks: [hook])
    cache2 = TestUtils.create_cache(hooks: [hook])
    cache3 = TestUtils.create_cache(hooks: [hook])
    cache4 = TestUtils.create_cache(hooks: [hook])

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
end
