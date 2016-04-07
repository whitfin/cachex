defmodule CachexTest.Expire do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "expire requires an existing cache name", _state do
    assert(Cachex.expire("test", "key", :timer.seconds(1)) == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "expire with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.expire(state_result, "key", 100) == { :missing, false })
  end

end
