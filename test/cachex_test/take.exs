defmodule CachexTest.Take do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "take requires an existing cache name", _state do
    assert(Cachex.take("test", "key") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "take with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.take(state_result, "key") == { :missing, nil })
  end

end
