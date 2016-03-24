defmodule CachexTest.Take do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "take requires an existing cache name", _state do
    assert(Cachex.take("test", "key") == { :error, "Invalid cache name provided, got: \"test\"" })
  end

end
