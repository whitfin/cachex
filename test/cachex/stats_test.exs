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
    results = Cachex.Stats.register(:clear, payload, stats)

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
    results1 = Cachex.Stats.register(:del, payload1, stats)

    # register the second payload
    results2 = Cachex.Stats.register(:del, payload2, results1)

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
    results1 = Cachex.Stats.register(:exists?, payload1, stats)

    # register the second payload
    results2 = Cachex.Stats.register(:exists?, payload2, results1)

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

  # Retrieving a key will increment the hit/miss/load counts based on whether the
  # key was in the cache, missing, or loaded via a fallback. Note that a fallback
  # will also increment the miss count (as a key must miss in order to fall back).
  test "registering get actions" do
    # create our base stats
    stats = %{ }

    # define our results
    payload1 = { :ok, "values" }
    payload2 = { :missing, nil }
    payload3 = { :loaded, "na" }

    # register the first payload
    results1 = Cachex.Stats.register(:get, payload1, stats)

    # register the second payload
    results2 = Cachex.Stats.register(:get, payload2, results1)

    # register the third payload
    results3 = Cachex.Stats.register(:get, payload3, results2)

    # verify the combined results
    assert(results3 == %{
      get: %{
        loaded: 1,
        missing: 1,
        ok: 1
      },
      global: %{
        hitCount: 1,
        loadCount: 1,
        missCount: 2,
        opCount: 3
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
    results = Cachex.Stats.register(:purge, payload, stats)

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
    results1 = Cachex.Stats.register(:set, payload1, stats)

    # register the second payload
    results2 = Cachex.Stats.register(:set, payload2, results1)

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
    results1 = Cachex.Stats.register(:take, payload1, stats)

    # register the second payload
    results2 = Cachex.Stats.register(:take, payload2, results1)

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
    results1 = Cachex.Stats.register(:ttl, payload1, stats)

    # register the second payload
    results2 = Cachex.Stats.register(:ttl, payload2, results1)

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

    # define registration actions
    register = fn(key, payload, acc) ->
      # register the payload
      Cachex.Stats.register(key, payload, acc)
    end

    # register the results
    new_stats = register.(:expire,    payload1,  stats)
    new_stats = register.(:expire,    payload2,  new_stats)
    new_stats = register.(:expire_at, payload1,  new_stats)
    new_stats = register.(:expire_at, payload2,  new_stats)
    new_stats = register.(:persist,   payload1,  new_stats)
    new_stats = register.(:persist,   payload2,  new_stats)
    new_stats = register.(:refresh,   payload1,  new_stats)
    new_stats = register.(:refresh,   payload2,  new_stats)
    new_stats = register.(:update,    payload1,  new_stats)
    new_stats = register.(:update,    payload2, new_stats)

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

    # define registration actions
    register = fn(key, payload, acc) ->
      # register the payload
      Cachex.Stats.register(key, payload, acc)
    end

    # register the results
    new_stats = register.(:get_and_update, payload1, stats)
    new_stats = register.(:get_and_update, payload2, new_stats)
    new_stats = register.(:incr, payload1, new_stats)
    new_stats = register.(:incr, payload2, new_stats)
    new_stats = register.(:decr, payload1, new_stats)
    new_stats = register.(:decr, payload2, new_stats)

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
      get_and_update: %{
        ok: 1,
        missing: 1
      },
      global: %{
        opCount: 6,
        setCount: 3,
        updateCount: 3
      }
    })
  end

end
