defmodule Cachex.Decr.RemoteTest do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache([remote: true]) }
  end

  test "decr with existing key using default amount", state do
    set_result = Cachex.set(state.cache, "my_key", 5)
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 5 })

    decr_result = Cachex.decr(state.cache, "my_key")
    assert(decr_result == { :ok, 4 })
  end

  test "decr with existing key using custom amount", state do
    set_result = Cachex.set(state.cache, "my_key", 5)
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 5 })

    decr_result = Cachex.decr(state.cache, "my_key", amount: 5)
    assert(decr_result == { :ok, 0 })
  end

  test "decr with missing key with no initial value", state do
    decr_result = Cachex.decr(state.cache, "my_key")
    assert(decr_result == { :missing, -1 })
  end

  test "decr with missing key with initial value", state do
    decr_result = Cachex.decr(state.cache, "my_key", initial: 5)
    assert(decr_result == { :missing, 4 })
  end

  test "decr with non-numeric value", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_value" })

    decr_result = Cachex.decr(state.cache, "my_key")
    assert(decr_result == { :error, "Unable to operate on non-numeric value" })
  end

end
