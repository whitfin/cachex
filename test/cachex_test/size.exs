defmodule CachexTest.Size do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "size requires an existing cache name", _state do
    assert(Cachex.size("test") == { :error, "Invalid cache name provided, got: \"test\"" })
  end

  test "size with an empty cache", state do
    size_result = Cachex.size(state.cache)
    assert(size_result == { :ok, 0 })
  end

  test "size with basic cache entries", state do
    Enum.each(1..20, fn(x) ->
      key = "my_key" <> to_string(x)

      set_result = Cachex.set(state.cache, key, "my_value")
      assert(set_result == { :ok, true })

      get_result = Cachex.get(state.cache, key)
      assert(get_result == { :ok, "my_value" })
    end)

    size_result = Cachex.size(state.cache)
    assert(size_result == { :ok, 20 })
  end

  test "size with some expired entries", state do
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

    size_result = Cachex.size(state.cache)
    assert(size_result == { :ok, 20 })
  end
  
end
