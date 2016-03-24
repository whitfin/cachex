defmodule CachexTest do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "defcheck macro cannot accept non-atom caches", _state do
    get_result = Cachex.get("test", "key")
    assert(get_result == { :error, "Invalid cache name provided, got: \"test\"" })
  end

  test "defcheck macro provides unsafe wrappers", state do
    set_result = Cachex.set!(state.cache, "key", "value")
    assert(set_result == true)

    get_result = Cachex.get!(state.cache, "key")
    assert(get_result == "value")

    assert_raise Cachex.ExecutionError, "Invalid cache name provided, got: \"test\"", fn ->
      Cachex.get!("test", "key")
    end
  end

end
