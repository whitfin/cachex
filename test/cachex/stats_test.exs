defmodule Cachex.StatsTest do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache([record_stats: true]) }
  end

  test "stats requires an existing cache name", _state do
    assert(Cachex.stats("test") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "stats with a worker instance", _state do
    cache = TestHelper.create_cache([record_stats: false])
    state_result = Cachex.inspect!(cache, :worker)
    assert(Cachex.stats(state_result) == { :error, "Stats not enabled for cache with ref '#{cache}'" })
  end

  test "stats returns an error if disabled", _state do
    cache = TestHelper.create_cache([record_stats: false])

    stats_result = Cachex.stats(cache)
    assert(stats_result == { :error, "Stats not enabled for cache with ref '#{cache}'" })
  end

  test "stats defaults to returning global statistics", state do
    creation_date = Cachex.Util.now()

    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    { stats_status, stats_result } = Cachex.stats(state.cache)

    assert(stats_status == :ok)
    refute(Map.has_key?(stats_result, :requestCount))

    get_result = Cachex.get(state.cache, "missing_key")
    assert(get_result == { :missing, nil })

    { stats_status, stats_result } = Cachex.stats(state.cache)

    assert(stats_status == :ok)
    assert(stats_result.hitRate == 0)
    assert(stats_result.missRate == 100)

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_value" })

    { stats_status, stats_result } = Cachex.stats(state.cache)

    assert(stats_status == :ok)
    assert(stats_result.hitCount == 1)
    assert(stats_result.hitRate == 0.5)
    assert(stats_result.missCount == 1)
    assert(stats_result.missRate == 0.5)
    assert(stats_result.opCount == 3)
    assert(stats_result.requestCount == 2)
    assert(stats_result.setCount == 1)
    assert_in_delta(stats_result.creationDate, creation_date, 5)
  end

  test "stats returns global as a key when requested separately", state do
    { stats_status, stats_result } = Cachex.stats(state.cache, for: [ :global ])

    assert(stats_status == :ok)
    refute(Map.has_key?(stats_result, :global))

    { stats_status, stats_result } = Cachex.stats(state.cache, for: [ :global, :get ])

    assert(stats_status == :ok)
    assert(Map.has_key?(stats_result, :get))
    assert(Map.has_key?(stats_result, :global))
  end

  test "stats can return the raw statistics", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_value" })

    { stats_status, stats_result } = Cachex.stats(state.cache, for: :raw)

    assert(stats_status == :ok)
    assert(Map.has_key?(stats_result, :meta))
    assert(stats_result[:get] == %{ ok: 1 })
    assert(stats_result[:set] == %{ true: 1 })
  end

end
