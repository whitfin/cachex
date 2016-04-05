defmodule CachexTest.Update do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "update requires an existing cache name", _state do
    assert(Cachex.update("test", "key", "value") == { :error, "Invalid cache provided, got: \"test\"" })
  end

end
