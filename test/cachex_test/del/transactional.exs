defmodule CachexTest.Del.Transactional do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache([transactional: true]) }
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

  test "del with async is faster than non-async", state do
    Enum.each(1..2, fn(x) ->
      key = "my_key" <> to_string(x)

      set_result = Cachex.set(state.cache, key, "my_value")
      assert(set_result == { :ok, true })

      get_result = Cachex.get(state.cache, key)
      assert(get_result == { :ok, "my_value" })
    end)

    { async_time, _res } = :timer.tc(fn ->
      Cachex.del(state.cache, "my_key1", async: true)
    end)

    { sync_time, _res } = :timer.tc(fn ->
      Cachex.del(state.cache, "my_key2", async: false)
    end)

    get_result = Cachex.get(state.cache, "my_key1")
    assert(get_result == { :missing, nil })
    assert(async_time < sync_time / 2)
  end

end
