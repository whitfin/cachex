defmodule CachexTest.Ttl do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "ttl requires an existing cache name", _state do
    assert(Cachex.ttl("test", "key") == { :error, "Invalid cache name provided, got: \"test\"" })
  end

end
