defmodule CachexTest.Ttl.Transactional do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache([transactional: true]) }
  end

  test "ttl with existing key with expiration", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value", ttl: :timer.seconds(1))
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_value" })

    { status, ttl } = Cachex.ttl(state.cache, "my_key")
    assert(status == :ok)
    assert_in_delta(ttl, 1000, 5)
  end

  test "ttl with existing key with no expiration", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_value" })

    ttl_result = Cachex.ttl(state.cache, "my_key")
    assert(ttl_result == { :ok, nil })
  end

  test "ttl with missing key", state do
    ttl_result = Cachex.ttl(state.cache, "my_key")
    assert(ttl_result == { :missing, nil })
  end

  test "ttl with expired key removes the key", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value", ttl: 5)
    assert(set_result == { :ok, true })

    :timer.sleep(10)

    ttl_result = Cachex.ttl(state.cache, "my_key")
    assert(ttl_result == { :missing, nil })
  end

end
