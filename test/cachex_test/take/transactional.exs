defmodule CachexTest.Take.Transactional do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache([transactional: true]) }
  end

  test "take with existing key", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_value" })

    take_result = Cachex.take(state.cache, "my_key")
    assert(take_result == { :ok, "my_value" })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :missing, nil })
  end

  test "take with missing key", state do
    take_result = Cachex.take(state.cache, "my_key")
    assert(take_result == { :ok, nil })
  end

end
