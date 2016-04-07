defmodule CachexTest.Clear do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "clear requires an existing cache name", _state do
    assert(Cachex.clear("test") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "clear with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.clear(state_result) == { :ok, 0 })
  end

end
