defmodule CachexTest.Stats do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache([record_stats: true]) }
  end

  test "stats requires an existing cache name", _state do
    assert(Cachex.stats("test") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "stats returns an error if disabled", _state do
    cache = TestHelper.create_cache([record_stats: false])

    stats_result = Cachex.stats(cache)
    assert(stats_result == { :error, "Stats not enabled for cache with ref '#{cache}'" })
  end

  test "stats adds a timestamp on initialization", state do
    { status, stats } = Cachex.stats(state.cache)
    assert(status == :ok)
    assert_in_delta(stats.creationDate, Cachex.Util.now(), 5)
  end

  test "stats adds various stats on retrieval", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_value" })

    get_result = Cachex.get(state.cache, "missing_key")
    assert(get_result == { :missing, nil })

    { stats_status, stats_result } = Cachex.stats(state.cache)

    assert(stats_status == :ok)
    assert(stats_result.hitCount == 1)
    assert(stats_result.hitRate == 0.5)
    assert(stats_result.missCount == 1)
    assert(stats_result.missRate == 0.5)
    assert(stats_result.opCount == 4)
    assert(stats_result.requestCount == 2)
    assert(stats_result.setCount == 2)
  end

end
