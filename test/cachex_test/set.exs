defmodule CachexTest.Set do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "set requires an existing cache name", _state do
    assert(Cachex.set("test", "key", "value") == { :error, "Invalid cache provided, got: \"test\"" })
  end
  
end
