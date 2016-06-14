defmodule Cachex.Del.RemoteTest do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache([remote: true]) }
  end

  test "del with existing key", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_value" })

    del_result = Cachex.del(state.cache, "my_key")
    assert(del_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :missing, nil })
  end

  test "del with missing key", state do
    del_result = Cachex.del(state.cache, "my_key")
    assert(del_result == { :ok, true })
  end

end
