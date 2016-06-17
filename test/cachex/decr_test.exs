defmodule Cachex.DecrTest do
  use PowerAssert, async: false

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "decr requires an existing cache name", _state do
    assert(Cachex.decr("test", "key") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "decr with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.decr(state_result, "key") == { :missing, -1 })
  end

end
