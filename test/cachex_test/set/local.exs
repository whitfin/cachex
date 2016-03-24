defmodule CachexTest.Set.Local do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "key set", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_value" })
  end

  test "key set with existing key", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_value" })

    set_result = Cachex.set(state.cache, "my_key", "my_new_value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_new_value" })
  end

  test "key set with expiration", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value", ttl: :timer.seconds(5))
    assert(set_result == { :ok, true })

    { status, ttl } = Cachex.ttl(state.cache, "my_key")
    assert(status == :ok)
    assert_in_delta(ttl, 5000, 5)
  end

  test "key set with default expiration", _state do
    cache = TestHelper.create_cache([ default_ttl: :timer.seconds(5) ])

    set_result = Cachex.set(cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    { status, ttl } = Cachex.ttl(cache, "my_key")
    assert(status == :ok)
    assert_in_delta(ttl, 5000, 5)
  end

  test "key set with overridden default expiration", _state do
    cache = TestHelper.create_cache([ default_ttl: :timer.seconds(5) ])

    set_result = Cachex.set(cache, "my_key", "my_value", ttl: :timer.seconds(10))
    assert(set_result == { :ok, true })

    { status, ttl } = Cachex.ttl(cache, "my_key")
    assert(status == :ok)
    assert_in_delta(ttl, 10000, 5)
  end

  test "key set with async is faster than non-async", state do
    { async_time, _res } = :timer.tc(fn ->
      Cachex.set(state.cache, "my_key1", "my_value1", async: true)
    end)

    { sync_time, _res } = :timer.tc(fn ->
      Cachex.set(state.cache, "my_key2", "my_value2", async: false)
    end)

    get_result = Cachex.get(state.cache, "my_key1")
    assert(get_result == { :ok, "my_value1" })
    assert(async_time < sync_time / 2)
  end

end
