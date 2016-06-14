defmodule Cachex.GetAndUpdateRawTest do
  use PowerAssert

  setup do
    cache = TestHelper.create_cache()
    { :ok, cache: cache, worker: Cachex.inspect!(cache, :state)}
  end

  test "get_and_update_raw with missing key", state do
    { :ok, gau_result } = Cachex.Worker.get_and_update_raw(state.worker, "my_key", fn
      ({ cache, key, touched, ttl, nil }) ->
        { cache, key, touched, ttl, 1 }
      ({ cache, key, touched, ttl, val }) ->
        { cache, key, touched, ttl, val }
    end)

    assert(elem(gau_result, 0) == state.cache)
    assert(elem(gau_result, 1) == "my_key")
    assert_in_delta(elem(gau_result, 2), Cachex.Util.now(), 2)
    assert(elem(gau_result, 3) == nil)
    assert(elem(gau_result, 4) == 1)

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 1 })
  end

  test "get_and_update_raw with existing key", state do
    set_result = Cachex.set(state.cache, "my_key", 5)
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 5 })

    { :ok, gau_result } = Cachex.Worker.get_and_update_raw(state.worker, "my_key", fn
      ({ cache, key, touched, ttl, nil }) ->
        { cache, key, touched, ttl, 1 }
      ({ cache, key, touched, ttl, val }) ->
        { cache, key, touched, ttl, val * 2 }
    end)

    assert(elem(gau_result, 0) == state.cache)
    assert(elem(gau_result, 1) == "my_key")
    assert_in_delta(elem(gau_result, 2), Cachex.Util.now(), 2)
    assert(elem(gau_result, 3) == nil)
    assert(elem(gau_result, 4) == 10)

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 10 })
  end

  test "get_and_update_raw with expired key", state do
    set_result = Cachex.set(state.cache, "my_key", 111, ttl: 5)
    assert(set_result == { :ok, true })

    :timer.sleep(10)

    { :ok, gau_result } = Cachex.Worker.get_and_update_raw(state.worker, "my_key", fn
      ({ cache, key, touched, ttl, nil }) ->
        { cache, key, touched, ttl, true }
      ({ cache, key, touched, ttl, 111 }) ->
        { cache, key, touched, ttl, false }
    end)

    assert(elem(gau_result, 0) == state.cache)
    assert(elem(gau_result, 1) == "my_key")
    assert_in_delta(elem(gau_result, 2), Cachex.Util.now(), 2)
    assert(elem(gau_result, 3) == nil)
    assert(elem(gau_result, 4) == true)
  end

  test "get_and_update_raw with touch/ttl times being maintained", state do
    now_result = Cachex.Util.now()
    set_result = Cachex.set(state.cache, "my_key", 5, ttl: 20)
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 5 })

    :timer.sleep(10)

    { :ok, gau_result } = Cachex.Worker.get_and_update_raw(state.worker, "my_key", &(&1))

    assert(elem(gau_result, 0) == state.cache)
    assert(elem(gau_result, 1) == "my_key")
    assert_in_delta(elem(gau_result, 2), now_result, 2)
    assert(elem(gau_result, 3) == 20)
    assert(elem(gau_result, 4) == 5)

    :timer.sleep(10)

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :missing, nil })
  end

end
