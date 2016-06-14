defmodule Cachex.RefreshTest do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "refresh requires an existing cache name", _state do
    assert(Cachex.refresh("test", "key") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "refresh with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.refresh(state_result, "key") == { :missing, false })
  end

end
