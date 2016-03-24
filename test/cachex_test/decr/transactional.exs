defmodule CachexTest.Decr.Transactional do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache([transactional: true]) }
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
    assert(decr_result == { :ok, -1 })
  end

  test "decr with missing key with initial value", state do
    decr_result = Cachex.decr(state.cache, "my_key", initial: 5)
    assert(decr_result == { :ok, 4 })
  end

  test "decr with async is faster than non-async", state do
    { async_time, _res } = :timer.tc(fn ->
      Cachex.decr(state.cache, "my_key1", async: true)
    end)

    { sync_time, _res } = :timer.tc(fn ->
      Cachex.decr(state.cache, "my_key2", async: false)
    end)

    assert(async_time < sync_time / 2)
  end

end
