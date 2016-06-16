defmodule Cachex.UpdateTest do
  use PowerAssert, async: false

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "update requires an existing cache name", _state do
    assert(Cachex.update("test", "key", "value") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "update with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.update(state_result, "key", "value") == { :missing, false })
  end

end
