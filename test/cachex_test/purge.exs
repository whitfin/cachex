defmodule CachexTest.Purge do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "purge requires an existing cache name", _state do
    assert(Cachex.purge("test") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "purge with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.purge(state_result) == { :ok, 0 })
  end

  test "purge with an empty cache", state do
    purge_result = Cachex.purge(state.cache)
    assert(purge_result == { :ok, 0 })
  end

  test "purge with a filled cache with no expirations", state do
    Enum.each(0..9, fn(x) ->
      key = "my_key" <> to_string(x)

      set_result = Cachex.set(state.cache, key, "my_value")
      assert(set_result == { :ok, true })

      get_result = Cachex.get(state.cache, key)
      assert(get_result == { :ok, "my_value" })
    end)

    purge_result = Cachex.purge(state.cache)
    assert(purge_result == { :ok, 0 })
  end

  test "purge with a filled cache with some expirations", state do
    Enum.each(0..4, fn(x) ->
      key = "my_key" <> to_string(x)

      set_result = Cachex.set(state.cache, key, "my_value", ttl: 1)
      assert(set_result == { :ok, true })

      get_result = Cachex.get(state.cache, key)
      assert(get_result == { :ok, "my_value" })
    end)

    Enum.each(5..9, fn(x) ->
      key = "my_key" <> to_string(x)

      set_result = Cachex.set(state.cache, key, "my_value")
      assert(set_result == { :ok, true })

      get_result = Cachex.get(state.cache, key)
      assert(get_result == { :ok, "my_value" })
    end)

    :timer.sleep(5)

    purge_result = Cachex.purge(state.cache)
    assert(purge_result == { :ok, 5 })
  end

  test "purge with a filled cache with all expirations", state do
    Enum.each(0..9, fn(x) ->
      key = "my_key" <> to_string(x)

      set_result = Cachex.set(state.cache, key, "my_value", ttl: 1)
      assert(set_result == { :ok, true })

      get_result = Cachex.get(state.cache, key)
      assert(get_result == { :ok, "my_value" })
    end)

    :timer.sleep(5)

    purge_result = Cachex.purge(state.cache)
    assert(purge_result == { :ok, 10 })
  end

  test "purge with async is faster than non-async", state do
    { async_time, _res } = :timer.tc(fn ->
      Cachex.purge(state.cache, async: true)
    end)

    { sync_time, _res } = :timer.tc(fn ->
      Cachex.purge(state.cache, async: false)
    end)

    assert(async_time < sync_time / 2)
  end

end
