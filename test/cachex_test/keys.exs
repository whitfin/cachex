defmodule CachexTest.Keys do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "keys requires an existing cache name", _state do
    assert(Cachex.keys("test") == { :error, "Invalid cache provided, got: \"test\"" })
  end
  
end
