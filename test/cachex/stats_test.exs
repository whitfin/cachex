defmodule Cachex.StatsTest do
  use CachexCase

  # This test ensures that we correctly register the clear action. When we clear
  # a cache, we need to increment the eviction count by the number of entries
  # evicted. We also increment the total key underneath the clear namespace by
  # the same number. The operation count in the global namespace also increments
  # by 1 (as clearing is a single cache op).
  test "registering clear actions" do
    # create a test cache
    cache = Helper.create_cache([ stats: true ])

    # set a few values in the cache
    for i <- 0..4 do
      { :ok, true } = Cachex.put(cache, i, i)
    end

    # clear the cache values
    { :ok, 5 } = Cachex.clear(cache)

    # retrieve the statistics
    { :ok, stats } = stats_no_meta(cache)

    # verify the statistics
    assert(stats == %{
      operations: 6,
      evictions: 5,
      writes: 5,
      calls: %{
        clear: 1,
        put: 5
      },
      expirations: 0,
      hits: 0,
      misses: 0,
      updates: 0
    })
  end

  # This test ensures that delete actions are correctly registered. We increment
  # the eviction count only in case of a successful eviction. We also increment
  # the result of the call (which is either true or false) under the del namespace.
  test "registering delete actions" do
    # create a test cache
    cache = Helper.create_cache([ stats: true ])

    # set a few values in the cache
    for i <- 0..1 do
      { :ok, true } = Cachex.put(cache, i, i)
    end

    # delete our cache values
    { :ok, true } = Cachex.del(cache, 0)
    { :ok, true } = Cachex.del(cache, 1)

    # retrieve the statistics
    { :ok, stats } = stats_no_meta(cache)

    # verify the statistics
    assert(stats == %{
      operations: 4,
      evictions: 2,
      writes: 2,
      calls: %{
        del: 2,
        put: 2
      },
      expirations: 0,
      hits: 0,
      misses: 0,
      updates: 0
    })
  end

  # This test verifies that exists actions correctly increment the necessary keys
  # inside the global and exists namespaces. We increment hit/miss counters in
  # the global namespace based on whether the key exists or not.
  test "registering exists? actions" do
    # create a test cache
    cache = Helper.create_cache([ stats: true ])

    # set a value in the cache
    { :ok, true } = Cachex.put(cache, 1, 1)

    # check for a couple of keys
    { :ok,  true } = Cachex.exists?(cache, 1)
    { :ok, false } = Cachex.exists?(cache, 2)

    # retrieve the statistics
    { :ok, stats } = stats_no_meta(cache)

    # verify the statistics
    assert(stats == %{
      operations: 3,
      writes: 1,
      hits: 1,
      misses: 1,
      hit_rate: 50.0,
      miss_rate: 50.0,
      calls: %{
        exists?: 2,
        put: 1
      },
      evictions: 0,
      expirations: 0,
      updates: 0
    })
  end

  # Retrieving a key will increment the hit/miss counts
  # based on whether the key was in the cache.
  test "registering get actions" do
    # create a test cache
    cache = Helper.create_cache([ stats: true ])

    # set a value in the cache
    { :ok, true } = Cachex.put(cache, 1, 1)

    # check for a couple of keys
    { :ok,   1 } = Cachex.get(cache, 1)
    { :ok, nil } = Cachex.get(cache, 2)

    # retrieve the statistics
    { :ok, stats } = stats_no_meta(cache)

    # verify the statistics
    assert(stats == %{
      operations: 3,
      writes: 1,
      hits: 1,
      misses: 1,
      hit_rate: 50.0,
      miss_rate: 50.0,
      calls: %{
        get: 2,
        put: 1
      },
      evictions: 0,
      expirations: 0,
      updates: 0
    })
  end

  # Retrieving a key will increment the hit/miss/load counts based on whether the
  # key was in the cache, missing, or loaded via a fallback. Note that a fallback
  # will also increment the miss count (as a key must miss in order to fall back).
  test "registering fetch actions" do
    # create a test cache
    cache = Helper.create_cache([ stats: true ])

    # set a value in the cache
    { :ok, true } = Cachex.put(cache, 1, 1)

    # fetch an existing value
    { :ok,        1 } = Cachex.fetch(cache, 1, fn _ -> { :commit, "na" } end)
    { :commit, "na" } = Cachex.fetch(cache, 2, fn _ -> { :commit, "na" } end)
    { :ignore, "na" } = Cachex.fetch(cache, 3, fn _ -> { :ignore, "na" } end)

    # retrieve the statistics
    { :ok, stats } = stats_no_meta(cache)

    # verify the statistics
    assert(stats == %{
      operations: 4,
      fetches: 2,
      writes: 2,
      hits: 1,
      hit_rate: (1 / 3) * 100,
      misses: 2,
      miss_rate: ((1 / 3) * 2) * 100,
      calls: %{
        fetch: 3,
        put: 1
      },
      evictions: 0,
      expirations: 0,
      updates: 0
    })
  end

  # These actions can update if the key exists, or set if the key does not exist.
  # This test will ensure both are done correctly, and appropriately to the result
  # of the action. If the key misses, we increment the setCount, if it hits we
  # increment the updateCount. Both increment the operation count.
  test "registering incr/decr actions" do
    # create a test cache
    cache = Helper.create_cache([ stats: true ])

    # incr values in the cache
    { :ok, 5 } = Cachex.incr(cache, 1, 3, initial: 2)
    { :ok, 6 } = Cachex.incr(cache, 1)

    # decr values in the cache
    { :ok, -5 } = Cachex.decr(cache, 2, 3, initial: -2)
    { :ok, -6 } = Cachex.decr(cache, 2)

    # retrieve the statistics
    { :ok, stats } = stats_no_meta(cache)

    # verify the statistics
    assert(stats == %{
      operations: 4,
      updates: 2,
      writes: 2,
      calls: %{
        incr: 2,
        decr: 2
      },
      evictions: 0,
      expirations: 0,
      hits: 0,
      misses: 0
    })
  end

  test "registering invoke actions" do
    # define some custom commands
    last = &List.last/1
    lpop = fn
      ([ head | tail ]) ->
        { head, tail }
      ([ ] = list) ->
        {  nil, list }
    end

    # create a test cache
    cache = Helper.create_cache([
      stats: true,
      commands: [
        last: command(type:  :read, execute: last),
        lpop: command(type: :write, execute: lpop)
      ]
    ])

    # put the base value
    { :ok, true } = Cachex.put(cache, "list", [ 1, 2, 3 ])

    # run each command
    { :ok, 3 } = Cachex.invoke(cache, :last, "list")
    { :ok, 1 } = Cachex.invoke(cache, :lpop, "list")

    # retrieve the statistics
    { :ok, stats } = stats_no_meta(cache)

    # verify the statistics
    assert(stats == %{
      operations: 6,
      updates: 1,
      writes: 1,
      hits: 2,
      hit_rate: 100.0,
      misses: 0,
      miss_rate: 0.0,
      invocations: %{
        last: 1,
        lpop: 1
      },
      calls: %{
        get: 2,
        invoke: 2,
        put: 1,
        update: 1
      },
      evictions: 0,
      expirations: 0
    })
  end

  # Very similar to the clear test above, with the same behaviour except for
  # incrementing the expiredCount in the global namespace rather than the typical
  # evictionCount. This is because purged keys are removed due to TTL expiration.
  test "registering purge actions" do
    # create a test cache
    cache = Helper.create_cache([ stats: true ])

    # set a few values in the cache
    for i <- 0..4 do
      { :ok, true } = Cachex.put(cache, i, i, ttl: 1)
    end

    # ensure purge
    :timer.sleep(5)

    # purge the cache values
    { :ok, 5 } = Cachex.purge(cache)

    # retrieve the statistics
    { :ok, stats } = stats_no_meta(cache)

    # verify the statistics
    assert(stats == %{
      expirations: 5,
      operations: 6,
      evictions: 5,
      writes: 5,
      calls: %{
        purge: 1,
        put: 5
      },
      hits: 0,
      misses: 0,
      updates: 0
    })
  end

  # This test ensures that a successful write will increment the setCount in the
  # global namespace, but otherwise only the false key is incremented inside the
  # set namespace, in order to avoid false positives.
  test "registering put actions" do
    # create a test cache
    cache = Helper.create_cache([ stats: true ])

    # set a few values in the cache
    for i <- 0..4 do
      { :ok, true } = Cachex.put(cache, i, i)
    end

    # retrieve the statistics
    { :ok, stats } = stats_no_meta(cache)

    # verify the statistics
    assert(stats == %{
      operations: 5,
      writes: 5,
      calls: %{
        put: 5
      },
      evictions: 0,
      expirations: 0,
      hits: 0,
      misses: 0,
      updates: 0
    })
  end

  # This operates in the same way as the test cases above, but verifies that
  # writing a batch will correctly count using the length of the batch itself.
  test "registering put_many actions" do
    # create a test cache
    cache = Helper.create_cache([ stats: true ])

    # set a few values in the cache
    { :ok, true } = Cachex.put_many(cache, [
      { 1, 1 }, { 2, 2 }, { 3, 3 }, { 4, 4 }, { 5, 5 }
    ])

    # retrieve the statistics
    { :ok, stats } = stats_no_meta(cache)

    # verify the statistics
    assert(stats == %{
      operations: 1,
      writes: 5,
      calls: %{
        put_many: 1
      },
      evictions: 0,
      expirations: 0,
      hits: 0,
      misses: 0,
      updates: 0
    })
  end

  # This test verifies the take action and the incremenation of the necessary keys.
  # We need to increment the evictionCount when a key is removed from the cache,
  # as well as the hitCount. If the key is not in the cache, then we increment the
  # missCount instead. Both also increment keys inside the take namespace.
  test "registering take actions" do
    # create a test cache
    cache = Helper.create_cache([ stats: true ])

    # set a value in the cache
    { :ok, true } = Cachex.put(cache, 1, 1)

    # delete our cache values
    { :ok, 1 } = Cachex.take(cache, 1)
    { :ok, nil } = Cachex.take(cache, 2)

    # retrieve the statistics
    { :ok, stats } = stats_no_meta(cache)

    # verify the statistics
    assert(stats == %{
      operations: 3,
      evictions: 1,
      writes: 1,
      hits: 1,
      hit_rate: 50.0,
      misses: 1,
      miss_rate: 50.0,
      calls: %{
        put: 1,
        take: 2
      },
      expirations: 0,
      updates: 0
    })
  end

  # This test verifies the update actions and the incremenation of the necessary keys.
  test "registering update actions" do
    # create a test cache
    cache = Helper.create_cache([ stats: true ])

    # set a value in the cache
    { :ok, true } = Cachex.put(cache, 1, 1)
    { :ok, true } = Cachex.touch(cache, 1)

    # retrieve the statistics
    { :ok, stats } = stats_no_meta(cache)

    # verify the statistics
    assert(stats == %{
      operations: 2,
      updates: 1,
      writes: 1,
      calls: %{
        put: 1,
        touch: 1
      },
      evictions: 0,
      expirations: 0,
      hits: 0,
      misses: 0
    })
  end

  # There's nothing more to test inside this hook beyond the ability to retrieve
  # the current state of the hook, and validate what it looks like after a couple
  # of stats have been incremented. Incrementation is done via the Cachex.Stats
  # module, so please refer to those tests for any issues with counters.
  test "retrieving the state of a stats hook" do
    # create a test cache
    cache = Helper.create_cache([ stats: true ])
    cache = Services.Overseer.retrieve(cache)

    # retrieve the current time
    ctime = now()

    # carry out some cache operations
    { :ok, true } = Cachex.put(cache, 1, 1)
    { :ok,    1 } = Cachex.get(cache, 1)

    # attempt to retrieve the cache stats
    { :ok, stats } = Cachex.Stats.retrieve(cache)

    # verify the state of the stats
    assert_in_delta(stats.meta.creation_date, ctime, 5)
    assert(stats.calls == %{ get: 1, put: 1 })
    assert(stats.hits == 1)
    assert(stats.writes == 1)
    assert(stats.operations == 2)
  end

  # Retrieves stats with no :meta field
  defp stats_no_meta(cache) do
    with { :ok, stats } <- Cachex.stats(cache) do
      { :ok, Map.delete(stats, :meta) }
    end
  end
end
