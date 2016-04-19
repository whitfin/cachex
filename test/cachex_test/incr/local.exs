defmodule CachexTest.Incr.Local do
  use PowerAssert

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

  test "incr with async is faster than non-async", state do
    { async_time, _res } = :timer.tc(fn ->
      Cachex.incr(state.cache, "my_key1", async: true)
    end)

    { sync_time, _res } = :timer.tc(fn ->
      Cachex.incr(state.cache, "my_key2", async: false)
    end)

    assert(async_time < sync_time / 2)
  end

end
