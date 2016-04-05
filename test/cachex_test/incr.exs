defmodule CachexTest.Incr do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "incr requires an existing cache name", _state do
    assert(Cachex.incr("test", "key") == { :error, "Invalid cache provided, got: \"test\"" })
  end
  
end
