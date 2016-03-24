defmodule CachexTest.Clear.Remote do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache([remote: true]) }
  end

  test "clear with empty cache", state do
    clear_result = Cachex.clear(state.cache)
    assert(clear_result == { :ok, 0 })
  end

  test "clear with filled cache", state do
    Enum.each(1..20, fn(x) ->
      key = "my_key" <> to_string(x)

      set_result = Cachex.set(state.cache, key, "my_value")
      assert(set_result == { :ok, true })

      get_result = Cachex.get(state.cache, key)
      assert(get_result == { :ok, "my_value" })
    end)

    clear_result = Cachex.clear(state.cache)
    assert(clear_result == { :ok, 20 })
  end

  test "clear with async is faster than non-async", state do
    { async_time, _res } = :timer.tc(fn ->
      Cachex.clear(state.cache, async: true)
    end)

    { sync_time, _res } = :timer.tc(fn ->
      Cachex.clear(state.cache, async: false)
    end)

    assert(async_time < sync_time / 2)
  end

end
