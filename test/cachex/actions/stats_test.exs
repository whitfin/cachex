defmodule Cachex.Actions.StatsTest do
  use CachexCase

  # This test covers stats retrieval by making sure that the numbers coming back
  # are both accurate and concise. We verify that the payload returned can be
  # filtered by the provided flags in order to customize output correctly.
  test "retrieving stats for a cache" do
    # create a test cache
    cache = Helper.create_cache([ record_stats: true ])

    # retrieve current time
    ctime = Cachex.Util.now()

    # execute some cache actions
    { :ok, true } = Cachex.set(cache, 1, 1)
    { :ok,    1 } = Cachex.get(cache, 1)

    # retrieve default stats
    stats1 = Cachex.stats!(cache)

    # retrieve global stats
    stats2 = Cachex.stats!(cache, [ for: [ :global, :get ] ])

    # retrieve specific stats
    stats3 = Cachex.stats!(cache, [ for: [ :get, :set ] ])

    # retrieve raw stats
    stats4 = Cachex.stats!(cache, [ for: :raw ])

    # verify the first returns a default stat struct
    assert_in_delta(stats1.creationDate, ctime, 5)
    assert(stats1.hitCount == 1)
    assert(stats1.hitRate == 100)
    assert(stats1.missRate == 0)
    assert(stats1.opCount == 2)
    assert(stats1.requestCount == 1)
    assert(stats1.setCount == 1)

    # verify the second returns the global entries under a global key
    assert(stats2 == %{
      get: %{
        ok: 1
      },
      global: %{
        hitCount: 1,
        opCount: 2,
        setCount: 1
      }
    })

    # verify the third returns only get/set stats
    assert(stats3 == %{
      get: %{
        ok: 1
      },
      set: %{
        true: 1
      }
    })

    # verify the fourth returns an entire payload
    assert_in_delta(stats4.meta.creationDate, ctime, 5)
    assert(stats4.get == %{ ok: 1 })
    assert(stats4.global == %{
      hitCount: 1,
      opCount: 2,
      setCount: 1
    })
    assert(stats4.set == %{ true: 1 })
  end

  # This test just verifies that we receive an error trying to retrieve stats
  # when they have already been disabled.
  test "retrieving stats from a diabled cache" do
    # create a test cache
    cache = Helper.create_cache([ record_stats: false ])

    # retrieve default stats
    stats = Cachex.stats(cache)

    # we should receive an error
    assert(stats == { :error, :stats_disabled })
  end

  # This test verifies that we correctly handle hit/miss rates when there are 0
  # values, to avoid arithmetic errors. We very 100% hit/miss rates, as well as
  # 50% either way.
  test "retrieving different rate combinations" do
    # create test caches
    cache1 = Helper.create_cache([ record_stats: true ])
    cache2 = Helper.create_cache([ record_stats: true ])
    cache3 = Helper.create_cache([ record_stats: true ])
    cache4 = Helper.create_cache([ record_stats: true ])

    # retrieve stats with no rates
    stats1 = Cachex.stats!(cache1)

    # get the stats keys
    keys1 = Map.keys(stats1)

    # there's nothing in the overview until something happens
    assert(keys1 == [ :creationDate ])

    # set cache1 to 100% misses
    { :missing, nil } = Cachex.get(cache1, 1)

    # set cache2 to 100% hits
    { :ok, true } = Cachex.set(cache2, 1, 1)
    { :ok,    1 } = Cachex.get(cache2, 1)

    # set cache3 to be 50% each way
    { :ok, true } = Cachex.set(cache3, 1, 1)
    { :ok,    1 } = Cachex.get(cache3, 1)
    { :missing, nil } = Cachex.get(cache3, 2)

    # set cache4 to have some loads
    { :loaded, 1 } = Cachex.get(cache4, 1, fallback: &(&1))

    # retrieve all cache rates
    stats2 = Cachex.stats!(cache1)
    stats3 = Cachex.stats!(cache2)
    stats4 = Cachex.stats!(cache3)
    stats5 = Cachex.stats!(cache4)

    # remove the creationDate
    stats2 = Map.delete(stats2, :creationDate)
    stats3 = Map.delete(stats3, :creationDate)
    stats4 = Map.delete(stats4, :creationDate)
    stats5 = Map.delete(stats5, :creationDate)

    # verify a 100% miss rate for cache1
    assert(stats2 == %{
      hitCount: 0,
      hitRate: 0.0,
      missCount: 1,
      missRate: 100.0,
      opCount: 1,
      requestCount: 1
    })

    # verify a 100% hit rate for cache2
    assert(stats3 == %{
      hitCount: 1,
      hitRate: 100.0,
      missCount: 0,
      missRate: 0.0,
      opCount: 2,
      requestCount: 1,
      setCount: 1
    })

    # verify a 50% hit rate for cache3
    assert(stats4 == %{
      hitCount: 1,
      hitRate: 50.0,
      missCount: 1,
      missRate: 50.0,
      opCount: 3,
      requestCount: 2,
      setCount: 1
    })

    # verify a load count for cache4
    assert(stats5 == %{
      hitCount: 0,
      hitRate: 0.0,
      loadCount: 1,
      missCount: 1,
      missRate: 100.0,
      opCount: 2,
      requestCount: 1,
      setCount: 1
    })
  end

end
