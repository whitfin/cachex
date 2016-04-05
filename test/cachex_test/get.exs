defmodule CachexTest.Get do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "get requires an existing cache name", _state do
    assert(Cachex.get("test", "key") == { :error, "Invalid cache provided, got: \"test\"" })
  end
  
end
