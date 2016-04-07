defmodule CachexTest.Del do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "del requires an existing cache name", _state do
    assert(Cachex.del("test", "key") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "del with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.del(state_result, "key") == { :ok, true })
  end

end
