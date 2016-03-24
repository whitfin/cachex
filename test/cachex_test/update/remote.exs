defmodule CachexTest.Update.Remote do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache([remote: true]) }
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

  test "update with async is faster than non-async", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value1")
    assert(set_result == { :ok, true })

    { async_time, _res } = :timer.tc(fn ->
      Cachex.update(state.cache, "my_key", "my_value2", async: true)
    end)

    { sync_time, _res } = :timer.tc(fn ->
      Cachex.update(state.cache, "my_key", "my_value3", async: false)
    end)

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_value3" })
    assert(async_time < sync_time / 2)
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
