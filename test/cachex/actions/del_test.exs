defmodule Cachex.Actions.DelTest do
  use PowerAssert, async: false

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "del requires an existing cache name", _state do
    assert(Cachex.del("test", "key") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "del with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.del(state_result, "key") == { :ok, true })
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
