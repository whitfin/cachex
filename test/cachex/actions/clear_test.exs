defmodule Cachex.Actions.ClearTest do
  use PowerAssert, async: false

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "clear requires an existing cache name", _state do
    assert(Cachex.clear("test") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "clear with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.clear(state_result) == { :ok, 0 })
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

end
