defmodule Cachex.Actions.UpdateTest do
  use PowerAssert, async: false

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "update requires an existing cache name", _state do
    assert(Cachex.update("test", "key", "value") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "update with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.update(state_result, "key", "value") == { :missing, false })
  end

  test "update with existing key", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_value" })

    update_result = Cachex.update(state.cache, "my_key", "my_new_value")
    assert(update_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_new_value" })
  end

  test "update with missing key returns error", state do
    update_result = Cachex.update(state.cache, "my_key", "my_value")
    assert(update_result == { :missing, false })
  end

  test "update with touch/ttl times being maintained", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value", ttl: 20)
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_value" })

    :timer.sleep(10)

    update_result = Cachex.update(state.cache, "my_key", "my_new_value")
    assert(update_result == { :ok, true })

    :timer.sleep(10)

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :missing, nil })
  end

end
