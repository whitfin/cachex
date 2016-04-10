defmodule CachexTest.GetAndUpdate do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "get and update requires an existing cache name", _state do
    assert(Cachex.get_and_update("test", "key", &(&1)) == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "get and update with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.get_and_update(state_result, "key", &(&1)) == { :missing, nil })
  end

  test "get and update with missing key", state do
    gau_result = Cachex.get_and_update(state.cache, "my_key", fn
      (nil) -> 1
      (val) -> val
    end)
    assert(gau_result == { :missing, 1 })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 1 })
  end

  test "get and update with existing key", state do
    set_result = Cachex.set(state.cache, "my_key", 5)
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 5 })

    gau_result = Cachex.get_and_update(state.cache, "my_key", fn
      (nil) -> 1
      (val) -> val * 2
    end)
    assert(gau_result == { :ok, 10 })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 10 })
  end

  test "get_and_update with fallback on existing key", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    gau_result = Cachex.get_and_update(state.cache, "my_key", &(String.reverse/1), fallback: &(&1))
    assert(gau_result == { :ok, "eulav_ym" })
  end

  test "get_and_update with fallback on missing key", state do
    gau_result = Cachex.get_and_update(state.cache, "my_key", &(String.reverse/1), fallback: &(&1))
    assert(gau_result == { :loaded, "yek_ym" })
  end

  test "get_and_update with default fallback", _state do
    gau_result =
      [ default_fallback: &(String.reverse/1)]
      |> TestHelper.create_cache
      |> Cachex.get_and_update("my_key", &(String.reverse/1))

    assert(gau_result == { :loaded, "my_key" })
  end

  test "get_and_update with overridden default fallback", _state do
    gau_result =
      [ default_fallback: &(String.reverse/1)]
      |> TestHelper.create_cache
      |> Cachex.get_and_update("my_key", &(String.reverse/1), fallback: &(&1))

    assert(gau_result == { :loaded, "yek_ym" })
  end

  test "get_and_update with fallback arguments and no arguments specified", _state do
    gau_result =
      [ fallback_args: ["1","2","3"] ]
      |> TestHelper.create_cache
      |> Cachex.get_and_update("my_key", &(String.reverse/1), fallback: fn -> "test" end)

    assert(gau_result == { :loaded, "tset" })
  end

  test "get_and_update with fallback arguments and single argument specified", _state do
    gau_result =
      [ fallback_args: ["1","2","3"] ]
      |> TestHelper.create_cache
      |> Cachex.get_and_update("my_key", &(String.reverse/1), fallback: &(&1))

    assert(gau_result == { :loaded, "yek_ym" })
  end

  test "get_and_update with fallback arguments and valid argument count specified", _state do
    gau_result =
      [ fallback_args: ["1","2","3"] ]
      |> TestHelper.create_cache
      |> Cachex.get_and_update("my_key", &(String.reverse/1), fallback: &(&1 <> &2 <> &3 <> &4))

    assert(gau_result == { :loaded, "321yek_ym" })
  end

  test "get_and_update with fallback arguments and invalid argument count specified", _state do
    gau_result =
      [ fallback_args: ["1","2","3"] ]
      |> TestHelper.create_cache
      |> Cachex.get_and_update("my_key", &(to_string/1), fallback: &(&1 <> &2 <> &3))

    assert(gau_result == { :missing, "" })
  end

  test "get_and_update with expired key", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value", ttl: 5)
    assert(set_result == { :ok, true })

    :timer.sleep(10)

    gau_result = Cachex.get_and_update(state.cache, "my_key", fn
      (nil) -> true
      (_na) -> false
    end)
    assert(gau_result == { :missing, true })
  end

  test "get and update with touch/ttl times being maintained", state do
    set_result = Cachex.set(state.cache, "my_key", 5, ttl: 20)
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 5 })

    :timer.sleep(10)

    gau_result = Cachex.get_and_update(state.cache, "my_key", &(&1))
    assert(gau_result == { :ok, 5 })

    :timer.sleep(10)

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :missing, nil })
  end

end
