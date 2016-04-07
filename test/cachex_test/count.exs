defmodule CachexTest.Count do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "count requires an existing cache name", _state do
    assert(Cachex.count("test") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "count with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.count(state_result) == { :ok, 0 })
  end

  test "count with an empty cache", state do
    count_result = Cachex.count(state.cache)
    assert(count_result == { :ok, 0 })
  end

  test "count with basic cache entries", state do
    Enum.each(1..20, fn(x) ->
      key = "my_key" <> to_string(x)

      set_result = Cachex.set(state.cache, key, "my_value")
      assert(set_result == { :ok, true })

      get_result = Cachex.get(state.cache, key)
      assert(get_result == { :ok, "my_value" })
    end)

    count_result = Cachex.count(state.cache)
    assert(count_result == { :ok, 20 })
  end

  test "count with some expired entries", state do
    Enum.each(1..10, fn(x) ->
      key = "my_key" <> to_string(x)

      set_result = Cachex.set(state.cache, key, "my_value", ttl: 1)
      assert(set_result == { :ok, true })
    end)

    Enum.each(11..20, fn(x) ->
      key = "my_key" <> to_string(x)

      set_result = Cachex.set(state.cache, key, "my_value")
      assert(set_result == { :ok, true })

      get_result = Cachex.get(state.cache, key)
      assert(get_result == { :ok, "my_value" })
    end)

    count_result = Cachex.count(state.cache)
    assert(count_result == { :ok, 10 })
  end

end
