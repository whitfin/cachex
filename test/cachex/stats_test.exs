defmodule Cachex.StatsTest do
  use CachexCase

  # This test ensures that we correctly register the clear action. When we clear
  # a cache, we need to increment the eviction count by the number of entries
  # evicted. We also increment the total key underneath the clear namespace by
  # the same number. The operation count in the global namespace also increments
  # by 1 (as clearing is a single cache op).
  test "registering clear actions" do
    # create our base stats
    stats = %{ }

    # define our results
    payload = { :ok, 5 }

    # registry the payload
    { :ok, results } = Cachex.Stats.handle_notify({ :clear, [] }, payload, stats)

    # verify the results
    assert(results == %{
      clear: %{
        total: 5
      },
      global: %{
        evictionCount: 5,
        opCount: 1
      }
    })
  end

  # This test ensures that delete actions are correctly registered. We increment
  # the eviction count only in case of a successful eviction. We also increment
  # the result of the call (which is either true or false) under the del namespace.
  test "registering delete actions" do
    # create our base stats
    stats = %{ }

    # define our results
    payload1 = { :ok, true }
    payload2 = { :ok, false }

    # register the first payload
    { :ok, results1 } = Cachex.Stats.handle_notify({ :del, [] }, payload1, stats)

    # register the second payload
    { :ok, results2 } = Cachex.Stats.handle_notify({ :del, [] }, payload2, results1)

    # verify the results
    assert(results2 == %{
      del: %{
        true: 1,
        false: 1
      },
      global: %{
        evictionCount: 1,
        opCount: 2
      }
    })
  end

  # This test verifies that exists actions correctly increment the necessary keys
  # inside the global and exists namespaces. We increment hit/miss counters in
  # the global namespace based on whether the key exists or not.
  test "registering exists? actions" do
    # create our base stats
    stats = %{ }

    # define our results
    payload1 = { :ok,  true }
    payload2 = { :ok, false }

    # register the first payload
    { :ok, results1 } = Cachex.Stats.handle_notify({ :exists?, [] }, payload1, stats)

    # register the second payload
    { :ok, results2 } = Cachex.Stats.handle_notify({ :exists?, [] }, payload2, results1)

    # verify the combined results
    assert(results2 == %{
      exists?: %{
        true: 1,
        false: 1
      },
      global: %{
        hitCount: 1,
        missCount: 1,
        opCount: 2
      }
    })
  end

  # Retrieving a key will increment the hit/miss counts
  # based on whether the key was in the cache.
  test "registering get actions" do
    # create our base stats
    stats = %{ }

    # define our results
    payload1 = { :ok, "values" }
    payload2 = { :missing, nil }

    # register the first payload
    { :ok, results1 } = Cachex.Stats.handle_notify({ :get, [] }, payload1, stats)

    # register the second payload
    { :ok, results2 } = Cachex.Stats.handle_notify({ :get, [] }, payload2, results1)

    # verify the combined results
    assert(results2 == %{
      get: %{
        missing: 1,
        ok: 1
      },
      global: %{
        hitCount: 1,
        missCount: 1,
        opCount: 2
      }
    })
  end

  # Retrieving a key will increment the hit/miss/load counts based on whether the
  # key was in the cache, missing, or loaded via a fallback. Note that a fallback
  # will also increment the miss count (as a key must miss in order to fall back).
  test "registering fetch actions" do
    # create our base stats
    stats = %{ }

    # define our results
    payload1 = { :ok, "values" }
    payload2 = { :missing, nil }
    payload3 = { :commit, "na" }
    payload4 = { :ignore, "na" }

    # register the first payload
    { :ok, results1 } = Cachex.Stats.handle_notify({ :fetch, [] }, payload1, stats)

    # register the second payload
    { :ok, results2 } = Cachex.Stats.handle_notify({ :fetch, [] }, payload2, results1)

    # register the third payload
    { :ok, results3 } = Cachex.Stats.handle_notify({ :fetch, [] }, payload3, results2)

    # register the fourth payload
    { :ok, results4 } = Cachex.Stats.handle_notify({ :fetch, [] }, payload4, results3)

    # verify the combined results
    assert(results4 == %{
      fetch: %{
        commit: 1,
        ignore: 1,
        missing: 1,
        ok: 1
      },
      global: %{
        hitCount: 1,
        loadCount: 2,
        missCount: 3,
        opCount: 4,
        setCount: 1
      }
    })
  end

  # Very similar to the clear test above, with the same behaviour except for
  # incrementing the expiredCount in the global namespace rather than the typical
  # evictionCount. This is because purged keys are removed due to TTL expiration.
  test "registering purge actions" do
    # create our base stats
    stats = %{ }

    # define our results
    payload = { :ok, 5 }

    # register the payload
    { :ok, results } = Cachex.Stats.handle_notify({ :purge, [] }, payload, stats)

    # verify the combined results
    assert(results == %{
      purge: %{
        total: 5
      },
      global: %{
        expiredCount: 5,
        opCount: 1
      }
    })
  end

  # This test ensures that a successful write will increment the setCount in the
  # global namespace, but otherwise only the false key is incremented inside the
  # set namespace, in order to avoid false positives.
  test "registering set actions" do
    # create our base stats
    stats = %{ }

    # define our results
    payload1 = { :ok, true }
    payload2 = { :ok, false }

    # register the first payload
    { :ok, results1 } = Cachex.Stats.handle_notify({ :set, [] }, payload1, stats)

    # register the second payload
    { :ok, results2 } = Cachex.Stats.handle_notify({ :set, [] }, payload2, results1)

    # verify the combined results
    assert(results2 == %{
      set: %{
        true: 1,
        false: 1
      },
      global: %{
        opCount: 2,
        setCount: 1
      }
    })
  end

  # This test verifies the take action and the incremenation of the necessary keys.
  # We need to increment the evictionCount when a key is removed from the cache,
  # as well as the hitCount. If the key is not in the cache, then we increment the
  # missCount instead. Both also increment keys inside the take namespace.
  test "registering take actions" do
    # create our base stats
    stats = %{ }

    # define our results
    payload1 = { :ok, "values" }
    payload2 = { :missing, nil }

    # register the first payload
    { :ok, results1 } = Cachex.Stats.handle_notify({ :take, [] }, payload1, stats)

    # register the second payload
    { :ok, results2 } = Cachex.Stats.handle_notify({ :take, [] }, payload2, results1)

    # verify the combined results
    assert(results2 == %{
      take: %{
        ok: 1,
        missing: 1
      },
      global: %{
        opCount: 2,
        evictionCount: 1,
        hitCount: 1,
        missCount: 1
      }
    })
  end

  # This test ensures that checking the TTL on a key correctly registers the stats
  # associated with the action. If the key doesn't exist, we ensure to increment
  # the miss count, otherwise we return the hit count. Both increment the op count.
  test "registering ttl actions" do
    # create our base stats
    stats = %{ }

    # define our results
    payload1 = { :ok, "values" }
    payload2 = { :missing, nil }

    # register the first payload
    { :ok, results1 } = Cachex.Stats.handle_notify({ :ttl, [] }, payload1, stats)

    # register the second payload
    { :ok, results2 } = Cachex.Stats.handle_notify({ :ttl, [] }, payload2, results1)

    # verify the combined results
    assert(results2 == %{
      ttl: %{
        ok: 1,
        missing: 1
      },
      global: %{
        opCount: 2,
        hitCount: 1,
        missCount: 1
      }
    })
  end

  # Update actions increment true/false based on whether the key exists or not.
  # They also incrment the updateCount key inside the global namespace based on
  # whether they were successful or not.
  test "registering update actions" do
    # create our base stats
    stats = %{ }

    # define our results
    payload1 = { :ok, true }
    payload2 = { :missing, false }

    # register the results
    { :ok, new_stats } = Cachex.Stats.handle_notify({ :expire, [] },    payload1,  stats)
    { :ok, new_stats } = Cachex.Stats.handle_notify({ :expire, [] },    payload2,  new_stats)
    { :ok, new_stats } = Cachex.Stats.handle_notify({ :expire_at, [] }, payload1,  new_stats)
    { :ok, new_stats } = Cachex.Stats.handle_notify({ :expire_at, [] }, payload2,  new_stats)
    { :ok, new_stats } = Cachex.Stats.handle_notify({ :persist, [] },   payload1,  new_stats)
    { :ok, new_stats } = Cachex.Stats.handle_notify({ :persist, [] },   payload2,  new_stats)
    { :ok, new_stats } = Cachex.Stats.handle_notify({ :refresh, [] },   payload1,  new_stats)
    { :ok, new_stats } = Cachex.Stats.handle_notify({ :refresh, [] },   payload2,  new_stats)
    { :ok, new_stats } = Cachex.Stats.handle_notify({ :update, [] },    payload1,  new_stats)
    { :ok, new_stats } = Cachex.Stats.handle_notify({ :update, [] },    payload2,  new_stats)

    # verify the combined results
    assert(new_stats == %{
      expire: %{
        true: 1,
        false: 1
      },
      expire_at: %{
        true: 1,
        false: 1
      },
      persist: %{
        true: 1,
        false: 1
      },
      refresh: %{
        true: 1,
        false: 1
      },
      update: %{
        true: 1,
        false: 1
      },
      global: %{
        opCount: 10,
        updateCount: 5
      }
    })
  end

  # These actions can update if the key exists, or set if the key does not exist.
  # This test will ensure both are done correctly, and appropriately to the result
  # of the action. If the key misses, we increment the setCount, if it hits we
  # increment the updateCount. Both increment the operation count.
  test "registering actions which can set or update" do
    # create our base stats
    stats = %{ }

    # define our results
    payload1 = { :ok, true }
    payload2 = { :missing, false }

    # register the results
    { :ok, new_stats } = Cachex.Stats.handle_notify({ :incr, [] }, payload1, stats)
    { :ok, new_stats } = Cachex.Stats.handle_notify({ :incr, [] }, payload2, new_stats)
    { :ok, new_stats } = Cachex.Stats.handle_notify({ :decr, [] }, payload1, new_stats)
    { :ok, new_stats } = Cachex.Stats.handle_notify({ :decr, [] }, payload2, new_stats)

    # verify the combined results
    assert(new_stats == %{
      decr: %{
        ok: 1,
        missing: 1
      },
      incr: %{
        ok: 1,
        missing: 1
      },
      global: %{
        opCount: 4,
        setCount: 2,
        updateCount: 2
      }
    })
  end

  # There's nothing more to test inside this hook beyond the ability to retrieve
  # the current state of the hook, and validate what it looks like after a couple
  # of stats have been incremented. Incrementation is done via the Cachex.Stats
  # module, so please refer to those tests for any issues with counters.
  test "retrieving the state of a stats hook" do
    # create a test cache
    cache = Helper.create_cache([ stats: true ])

    # retrieve the current time
    ctime = now()

    # carry out some cache operations
    { :ok, true } = Cachex.set(cache, 1, 1)
    { :ok,    1 } = Cachex.get(cache, 1)

    # generate the name of the stats hook
    sname = name(cache, :stats)

    # attempt to retrieve the cache stats
    stats = GenServer.call(sname, :retrieve)

    # verify the state of the stats
    assert_in_delta(stats.meta.creationDate, ctime, 5)
    assert(stats.get == %{ ok: 1 })
    assert(stats.global == %{ hitCount: 1, opCount: 2, setCount: 1 })
    assert(stats.set == %{ true: 1 })
  end
end
