defmodule CachexTest.Refresh do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "refresh requires an existing cache name", _state do
    assert(Cachex.refresh("test", "key") == { :error, "Invalid cache provided, got: \"test\"" })
  end
  
end
