defmodule Cachex.SetTest do
  use PowerAssert, async: false

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "set requires an existing cache name", _state do
    assert(Cachex.set("test", "key", "value") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "set with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.set(state_result, "key", "value") == { :ok, true })
  end

end
