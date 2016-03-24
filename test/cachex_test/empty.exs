defmodule CachexTest.Empty do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "empty? requires an existing cache name", _state do
    assert(Cachex.empty?("test") == { :error, "Invalid cache name provided, got: \"test\"" })
  end

  test "empty? with values in the cache", state do
    set_result = Cachex.set(state.cache, "my_key", 5)
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 5 })

    empty_result = Cachex.empty?(state.cache)
    assert(empty_result == { :ok, false })
  end

  test "empty? with no values in the cache", state do
    empty_result = Cachex.empty?(state.cache)
    assert(empty_result == { :ok, true })
  end

end
