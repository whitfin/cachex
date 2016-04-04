defmodule CachexTest.Get.Remote do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache([remote: true]) }
  end

  test "key get with existing key", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_value" })
  end

  test "key get with missing key", state do
    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :missing, nil })
  end

  test "key get with fallback on existing key", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key", fallback: &(&1))
    assert(get_result == { :ok, "my_value" })
  end

  test "key get with fallback on missing key", state do
    get_result = Cachex.get(state.cache, "my_key", fallback: &(&1))
    assert(get_result == { :loaded, "my_key" })
  end

  test "key get with default fallback", _state do
    get_result =
      [ default_fallback: &(String.reverse/1)]
      |> TestHelper.create_cache
      |> Cachex.get("my_key")

    assert(get_result == { :loaded, "yek_ym" })
  end

  test "key get with overridden default fallback", _state do
    get_result =
      [ default_fallback: &(String.reverse/1)]
      |> TestHelper.create_cache
      |> Cachex.get("my_key", fallback: &(&1))

    assert(get_result == { :loaded, "my_key" })
  end

  test "key get with fallback arguments and no arguments specified", _state do
    get_result =
      [ fallback_args: ["1","2","3"] ]
      |> TestHelper.create_cache
      |> Cachex.get("my_key", fallback: fn -> "test" end)

    assert(get_result == { :loaded, "test" })
  end

  test "key get with fallback arguments and single argument specified", _state do
    get_result =
      [ fallback_args: ["1","2","3"] ]
      |> TestHelper.create_cache
      |> Cachex.get("my_key", fallback: &(&1))

    assert(get_result == { :loaded, "my_key" })
  end

  test "key get with fallback arguments and valid argument count specified", _state do
    get_result =
      [ fallback_args: ["1","2","3"] ]
      |> TestHelper.create_cache
      |> Cachex.get("my_key", fallback: &(&1 <> &2 <> &3 <> &4))

    assert(get_result == { :loaded, "my_key123" })
  end

  test "key get with fallback arguments and invalid argument count specified", _state do
    get_result =
      [ fallback_args: ["1","2","3"] ]
      |> TestHelper.create_cache
      |> Cachex.get("my_key", fallback: &(&1 <> &2 <> &3))

    assert(get_result == { :missing, nil })
  end

  test "key get with expired key", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value", ttl: 5)
    assert(set_result == { :ok, true })

    :timer.sleep(10)

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :missing, nil })
  end

end
