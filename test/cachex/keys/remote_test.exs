defmodule Cachex.Keys.RemoteTest do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache([remote: true]) }
  end

  test "keys with an empty cache", state do
    keys_result = Cachex.keys(state.cache)
    assert(keys_result == { :ok, [] })
  end

  test "keys with some cache entries", state do
    Enum.each(0..9, fn(x) ->
      key = "my_key" <> to_string(x)

      set_result = Cachex.set(state.cache, key, "my_value")
      assert(set_result == { :ok, true })

      get_result = Cachex.get(state.cache, key)
      assert(get_result == { :ok, "my_value" })
    end)

    { keys_status, keys_list } = Cachex.keys(state.cache)
    assert(keys_status == :ok)

    keys_list
    |> Enum.sort
    |> Enum.with_index
    |> Enum.each(fn({ key, index }) ->
        assert(key == "my_key" <> to_string(index))
       end)
  end

  test "keys with some expired entries", state do
    Enum.each(0..9, fn(x) ->
      key = "my_key" <> to_string(x)

      set_result = Cachex.set(state.cache, key, "my_value")
      assert(set_result == { :ok, true })
    end)

    Enum.each(10..19, fn(x) ->
      key = "my_key" <> to_string(x)

      set_result = Cachex.set(state.cache, key, "my_value", ttl: 1)
      assert(set_result == { :ok, true })

      get_result = Cachex.get(state.cache, key)
      assert(get_result == { :ok, "my_value" })
    end)

    :timer.sleep(1)

    { keys_status, keys_list } = Cachex.keys(state.cache)
    assert(keys_status == :ok)

    keys_list
    |> Enum.sort
    |> Enum.with_index
    |> Enum.each(fn({ key, index }) ->
        assert(key == "my_key" <> to_string(index))
       end)
  end

end
