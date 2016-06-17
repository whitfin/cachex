defmodule Cachex.IncrTest do
  use PowerAssert, async: false

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "incr requires an existing cache name", _state do
    assert(Cachex.incr("test", "key") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "incr with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.incr(state_result, "key") == { :missing, 1 })
  end

end
