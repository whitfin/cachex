defmodule CachexTest.Del do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "del requires an existing cache name", _state do
    assert(Cachex.del("test", "key") == { :error, "Invalid cache name provided, got: \"test\"" })
  end
  
end
