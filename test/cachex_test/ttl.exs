defmodule CachexTest.Ttl do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "ttl requires an existing cache name", _state do
    assert(Cachex.ttl("test", "key") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "ttl with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.ttl(state_result, "key") == { :missing, nil })
  end

end
