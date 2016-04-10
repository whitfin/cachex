defmodule CachexTest.Stats do
  use PowerAssert

  @status_based %{
    expire: [ 1000 ],
    expire_at: [ Cachex.Util.now() + :timer.minutes(1) ],
    persist: [ ],
    refresh: [ ],
    take: [ ],
    ttl: [ ]
  }

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

  test "stats correctly tracks status based functions", state do
    Enum.each(@status_based, fn({ action, args }) ->
      set_result = Cachex.set(state.cache, "my_key", 1)
      assert(set_result == { :ok, true })

      { result, _value } = apply(Cachex, action, [state.cache|["my_key"|args]])
      assert({ action, result } == { action, :ok })

      { result, _value } = apply(Cachex, action, [state.cache|["missing_key"|args]])
      assert({ action, result } == { action, :missing })

      { stats_status, stats_result } = Cachex.stats(state.cache, for: action)

      assert(stats_status == :ok)
      assert(Enum.count(stats_result) == 2)
      assert(stats_result[action] == %{ ok: 1, missing: 1 })
    end)
  end

  test "stats correctly tracks loadable based functions", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_value" })

    get_result = Cachex.get(state.cache, "missing_key")
    assert(get_result == { :missing, nil })

    get_result = Cachex.get(state.cache, "missing_key", fallback: &(&1))
    assert(get_result == { :loaded, "missing_key" })

    Cachex.del(state.cache, "missing_key")

    get_result = Cachex.get_and_update(state.cache, "missing_key", &(&1), fallback: &(&1))
    assert(get_result == { :loaded, "missing_key" })

    { stats_status, stats_result } = Cachex.stats(state.cache, for: [ :get, :get_and_update ])

    assert(stats_status == :ok)
    assert(Enum.count(stats_result) == 3)
    assert(stats_result[:get] == %{ ok: 1, loaded: 1, missing: 1 })
    assert(stats_result[:get_and_update] == %{ loaded: 1 })
  end

  test "stats correctly tracks value based functions", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    exists_result = Cachex.exists?(state.cache, "my_key")
    assert(exists_result == { :ok, true })

    del_result = Cachex.del(state.cache, "my_key")
    assert(del_result == { :ok, true })

    exists_result = Cachex.exists?(state.cache, "my_key")
    assert(exists_result == { :ok, false })

    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    update_result = Cachex.update(state.cache, "my_key", "new_value")
    assert(update_result == { :ok, true })

    { stats_status, stats_result } = Cachex.stats(state.cache, for: [ :set, :del, :exists?, :update ])

    assert(stats_status == :ok)
    assert(Enum.count(stats_result) == 5)
    assert(stats_result[:del] == %{ true: 1 })
    assert(stats_result[:set] == %{ true: 2 })
    assert(stats_result[:exists?] == %{ true: 1, false: 1 })
    assert(stats_result[:update] == %{ true: 1 })
  end

  test "stats correctly tracks amount based functions", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value", ttl: 1)
    assert(set_result == { :ok, true })

    :timer.sleep(3)

    purge_result = Cachex.purge(state.cache)
    assert(purge_result == { :ok, 1 })

    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    clear_result = Cachex.clear(state.cache)
    assert(clear_result == { :ok, 1 })

    { stats_status, stats_result } = Cachex.stats(state.cache, for: [ :clear, :purge ])

    assert(stats_status == :ok)
    assert(Enum.count(stats_result) == 3)
    assert(stats_result[:clear] == %{ total: 1 })
    assert(stats_result[:purge] == %{ total: 1 })

    { stats_status, stats_result } = Cachex.stats(state.cache)

    assert(stats_status == :ok)
    assert(stats_result[:evictionCount] == 1)
    assert(stats_result[:expiredCount] == 1)
  end

  test "stats correctly tracks call based functions", state do
    keys_result = Cachex.keys(state.cache)
    assert(keys_result == { :ok, [ ] })

    { stats_status, stats_result } = Cachex.stats(state.cache, for: [ :keys ])

    assert(stats_status == :ok)
    assert(Enum.count(stats_result) == 2)
    assert(stats_result[:keys] == %{ calls: 1 })
  end

end
