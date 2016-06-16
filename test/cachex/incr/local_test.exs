defmodule Cachex.Incr.LocalTest do
  use PowerAssert, async: false

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "incr with existing key using default amount", state do
    set_result = Cachex.set(state.cache, "my_key", 5)
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 5 })

    incr_result = Cachex.incr(state.cache, "my_key")
    assert(incr_result == { :ok, 6 })
  end

  test "incr with existing key using custom amount", state do
    set_result = Cachex.set(state.cache, "my_key", 5)
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 5 })

    incr_result = Cachex.incr(state.cache, "my_key", amount: 5)
    assert(incr_result == { :ok, 10 })
  end

  test "incr with missing key with no initial value", state do
    incr_result = Cachex.incr(state.cache, "my_key")
    assert(incr_result == { :missing, 1 })
  end

  test "incr with missing key with initial value", state do
    incr_result = Cachex.incr(state.cache, "my_key", initial: 5)
    assert(incr_result == { :missing, 6 })
  end

  test "incr with non-numeric value", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_value" })

    incr_result = Cachex.incr(state.cache, "my_key")
    assert(incr_result == { :error, "Unable to operate on non-numeric value" })
  end

end
