defmodule Cachex.GetTest do
  use PowerAssert, async: false

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "get requires an existing cache name", _state do
    assert(Cachex.get("test", "key") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "get with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.get(state_result, "key") == { :missing, nil })
  end

end
