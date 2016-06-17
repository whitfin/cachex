defmodule Cachex.Stats.Registry.RemoteTest do
  use PowerAssert, async: false

  setup do
    { :ok, cache: TestHelper.create_cache([record_stats: true, remote: true]) }
  end

  test "stats with a clear action", state do
    set_result = Cachex.set(state.cache, "key1", "value")
    assert(set_result == { :ok, true })

    set_result = Cachex.set(state.cache, "key2", "value")
    assert(set_result == { :ok, true })

    clear_result = Cachex.clear(state.cache)
    assert(clear_result == { :ok, 2 })

    { status, stats } = Cachex.stats(state.cache, for: :raw)

    assert(status == :ok)
    assert(stats[:clear] == %{ total: 2 })
    assert(stats[:global] == %{ evictionCount: 2, opCount: 3, setCount: 2 })
  end

  test "stats with a count action", state do
    count_result = Cachex.count(state.cache)
    assert(count_result == { :ok, 0 })

    { status, stats } = Cachex.stats(state.cache, for: :raw)

    assert(status == :ok)
    assert(stats[:count] == %{ calls: 1 })
    assert(stats[:global] == %{ opCount: 1 })
  end

  test "stats with an decr action", state do
    set_result = Cachex.set(state.cache, "key", 1)
    assert(set_result == { :ok, true })

    decr_result = Cachex.decr(state.cache, "key")
    assert(decr_result == { :ok, 0 })

    decr_result = Cachex.decr(state.cache, "missing_key")
    assert(decr_result == { :missing, -1 })

    { status, stats } = Cachex.stats(state.cache, for: :raw)

    assert(status == :ok)
    assert(stats[:decr] == %{ ok: 1, missing: 1 })
    # setCount is 2 because missing keys are set
    # updateCount is 1 because only :ok is an update
    assert(stats[:global] == %{ opCount: 3, setCount: 2, updateCount: 1 })
  end

  test "stats with a del action", state do
    set_result = Cachex.set(state.cache, "key", "value")
    assert(set_result == { :ok, true })

    del_result = Cachex.del(state.cache, "key")
    assert(del_result == { :ok, true })

    { status, stats } = Cachex.stats(state.cache, for: :raw)

    assert(status == :ok)
    assert(stats[:del] == %{ true: 1 })
    assert(stats[:global] == %{ evictionCount: 1, opCount: 2, setCount: 1 })
  end

  test "stats with an exists? action", state do
    set_result = Cachex.set(state.cache, "key", "value")
    assert(set_result == { :ok, true })

    exists_result = Cachex.exists?(state.cache, "key")
    assert(exists_result == { :ok, true })

    exists_result = Cachex.exists?(state.cache, "missing_key")
    assert(exists_result == { :ok, false })

    { status, stats } = Cachex.stats(state.cache, for: :raw)

    assert(status == :ok)
    assert(stats[:exists?] == %{ true: 1, false: 1 })
    assert(stats[:global] == %{ opCount: 3, setCount: 1, hitCount: 1, missCount: 1 })
  end

  test "stats with an expire action", state do
    set_result = Cachex.set(state.cache, "key", "value")
    assert(set_result == { :ok, true })

    expire_result = Cachex.expire(state.cache, "key", 5000)
    assert(expire_result == { :ok, true })

    expire_result = Cachex.expire(state.cache, "missing_key", 5000)
    assert(expire_result == { :missing, false })

    { status, stats } = Cachex.stats(state.cache, for: :raw)

    assert(status == :ok)
    assert(stats[:expire] == %{ true: 1, false: 1 })
    assert(stats[:global] == %{ opCount: 3, updateCount: 1, setCount: 1 })
  end

  test "stats with an expire_at action", state do
    set_result = Cachex.set(state.cache, "key", "value")
    assert(set_result == { :ok, true })

    expire_at_result = Cachex.expire_at(state.cache, "key", Cachex.Util.now() + 5000)
    assert(expire_at_result == { :ok, true })

    expire_at_result = Cachex.expire_at(state.cache, "missing_key", Cachex.Util.now() + 5000)
    assert(expire_at_result == { :missing, false })

    { status, stats } = Cachex.stats(state.cache, for: :raw)

    assert(status == :ok)
    assert(stats[:expire_at] == %{ true: 1, false: 1 })
    assert(stats[:global] == %{ opCount: 3, updateCount: 1, setCount: 1 })
  end

  test "stats with a get action", state do
    set_result = Cachex.set(state.cache, "key", "value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "key")
    assert(get_result == { :ok, "value" })

    get_result = Cachex.get(state.cache, "missing_key")
    assert(get_result == { :missing, nil })

    get_result = Cachex.get(state.cache, "missing_key", fallback: &(&1))
    assert(get_result == { :loaded, "missing_key" })

    set_result = Cachex.set(state.cache, "key", "value", ttl: 1)
    assert(set_result == { :ok, true })

    :timer.sleep(2)

    get_result = Cachex.get(state.cache, "key")
    assert(get_result == { :missing, nil })

    { status, stats } = Cachex.stats(state.cache, for: :raw)

    assert(status == :ok)
    assert(stats[:get] == %{ ok: 1, missing: 2, loaded: 1 })
    # setCount is 2 fallbacks also do a set into the cache
    # missCount is 2 because loading a key also is a miss
    assert(stats[:global] == %{ opCount: 8, expiredCount: 1, setCount: 3, hitCount: 1, missCount: 3, loadCount: 1 })
  end

  test "stats with a get_and_update action", state do
    set_result = Cachex.set(state.cache, "key", "value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get_and_update(state.cache, "key", &(&1))
    assert(get_result == { :ok, "value" })

    get_result = Cachex.get_and_update(state.cache, "missing_key", &(&1))
    assert(get_result == { :missing, nil })

    get_result = Cachex.get_and_update(state.cache, "another_missing_key", &(&1), fallback: &(&1))
    assert(get_result == { :loaded, "another_missing_key" })

    { status, stats } = Cachex.stats(state.cache, for: :raw)

    assert(status == :ok)
    assert(stats[:get_and_update] == %{ ok: 1, missing: 1, loaded: 1 })
    # opCount is 4 because fallbacks don't set before being used as an update
    # setCount is 3 because loaded keys are set, not updates
    # updateCount is 1 because only :ok is an update
    assert(stats[:global] == %{ opCount: 4, setCount: 3, updateCount: 1 })
  end

  test "stats with an incr action", state do
    set_result = Cachex.set(state.cache, "key", 1)
    assert(set_result == { :ok, true })

    incr_result = Cachex.incr(state.cache, "key")
    assert(incr_result == { :ok, 2 })

    incr_result = Cachex.incr(state.cache, "missing_key")
    assert(incr_result == { :missing, 1 })

    { status, stats } = Cachex.stats(state.cache, for: :raw)

    assert(status == :ok)
    assert(stats[:incr] == %{ ok: 1, missing: 1 })
    # setCount is 2 because missing keys are set
    # updateCount is 1 because only :ok is an update
    assert(stats[:global] == %{ opCount: 3, setCount: 2, updateCount: 1 })
  end

  test "stats with a keys action", state do
    keys_result = Cachex.keys(state.cache)
    assert(keys_result == { :ok, [] })

    { status, stats } = Cachex.stats(state.cache, for: :raw)

    assert(status == :ok)
    assert(stats[:keys] == %{ calls: 1 })
    assert(stats[:global] == %{ opCount: 1 })
  end

  test "stats with a persist action", state do
    set_result = Cachex.set(state.cache, "key", "value")
    assert(set_result == { :ok, true })

    persist_result = Cachex.persist(state.cache, "key")
    assert(persist_result == { :ok, true })

    persist_result = Cachex.persist(state.cache, "missing_key")
    assert(persist_result == { :missing, false })

    { status, stats } = Cachex.stats(state.cache, for: :raw)

    assert(status == :ok)
    assert(stats[:persist] == %{ true: 1, false: 1 })
    assert(stats[:global] == %{ opCount: 3, updateCount: 1, setCount: 1 })
  end

  test "stats with a purge action", _state do
    cache = TestHelper.create_cache(record_stats: true)

    set_result = Cachex.set(cache, "key1", 1, ttl: 1)
    assert(set_result == { :ok, true })

    set_result = Cachex.set(cache, "key2", 1, ttl: 1)
    assert(set_result == { :ok, true })

    :timer.sleep(2)

    purge_result = Cachex.purge(cache)
    assert(purge_result == { :ok, 2 })

    { status, stats } = Cachex.stats(cache, for: :raw)

    assert(status == :ok)
    assert(stats[:purge] == %{ total: 2 })
    assert(stats[:global] == %{ opCount: 3, setCount: 2, expiredCount: 2 })
  end

  test "stats with a refresh action", state do
    set_result = Cachex.set(state.cache, "key", "value")
    assert(set_result == { :ok, true })

    refresh_result = Cachex.refresh(state.cache, "key")
    assert(refresh_result == { :ok, true })

    refresh_result = Cachex.refresh(state.cache, "missing_key")
    assert(refresh_result == { :missing, false })

    { status, stats } = Cachex.stats(state.cache, for: :raw)

    assert(status == :ok)
    assert(stats[:refresh] == %{ true: 1, false: 1 })
    assert(stats[:global] == %{ opCount: 3, updateCount: 1, setCount: 1 })
  end

  test "stats with a set action", state do
    set_result = Cachex.set(state.cache, "key", 1)
    assert(set_result == { :ok, true })

    { status, stats } = Cachex.stats(state.cache, for: :raw)

    assert(status == :ok)
    assert(stats[:set] == %{ true: 1 })
    assert(stats[:global] == %{ opCount: 1, setCount: 1 })
  end

  test "stats with a size action", state do
    size_result = Cachex.size(state.cache)
    assert(size_result == { :ok, 0 })

    { status, stats } = Cachex.stats(state.cache, for: :raw)

    assert(status == :ok)
    assert(stats[:size] == %{ calls: 1 })
    assert(stats[:global] == %{ opCount: 1 })
  end

  test "stats with a take action", state do
    set_result = Cachex.set(state.cache, "key", 1)
    assert(set_result == { :ok, true })

    take_result = Cachex.take(state.cache, "key")
    assert(take_result == { :ok, 1 })

    take_result = Cachex.take(state.cache, "key")
    assert(take_result == { :missing, nil })

    { status, stats } = Cachex.stats(state.cache, for: :raw)

    assert(status == :ok)
    assert(stats[:take] == %{ ok: 1, missing: 1 })
    assert(stats[:global] == %{ opCount: 3, setCount: 1, hitCount: 1, missCount: 1, evictionCount: 1 })
  end

  test "stats with a ttl action", state do
    set_result = Cachex.set(state.cache, "key", 1, ttl: :timer.seconds(5))
    assert(set_result == { :ok, true })

    take_result = Cachex.ttl(state.cache, "key")
    assert(elem(take_result, 0) == :ok)
    assert_in_delta(elem(take_result, 1), 1000, 5000)

    take_result = Cachex.ttl(state.cache, "missing_key")
    assert(take_result == { :missing, nil })

    { status, stats } = Cachex.stats(state.cache, for: :raw)

    assert(status == :ok)
    assert(stats[:ttl] == %{ ok: 1, missing: 1 })
    # no hits or misses, as this is not explicit retrieval
    assert(stats[:global] == %{ opCount: 3, setCount: 1 })
  end

  test "stats with an update action", state do
    set_result = Cachex.set(state.cache, "key", 1)
    assert(set_result == { :ok, true })

    update_result = Cachex.update(state.cache, "key", "value")
    assert(update_result == { :ok, true })

    update_result = Cachex.update(state.cache, "missing_key", "value")
    assert(update_result == { :missing, false })

    { status, stats } = Cachex.stats(state.cache, for: :raw)

    assert(status == :ok)
    assert(stats[:update] == %{ true: 1, false: 1 })
    assert(stats[:global] == %{ opCount: 3, setCount: 1, updateCount: 1 })
  end

end
