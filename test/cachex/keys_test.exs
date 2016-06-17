defmodule Cachex.KeysTest do
  use PowerAssert, async: false

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "keys requires an existing cache name", _state do
    assert(Cachex.keys("test") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "keys with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.keys(state_result) == { :ok, [] })
  end

end
