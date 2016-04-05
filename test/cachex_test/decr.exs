defmodule CachexTest.Decr do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "decr requires an existing cache name", _state do
    assert(Cachex.decr("test", "key") == { :error, "Invalid cache provided, got: \"test\"" })
  end
  
end
