defmodule CachexTest.Clear do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "clear requires an existing cache name", _state do
    assert(Cachex.clear("test") == { :error, "Invalid cache provided, got: \"test\"" })
  end
  
end
