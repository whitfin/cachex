defmodule CachexTest.Expire.Remote do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache([remote: true]) }
  end

  test "expire with an existing key and no ttl", state do
    set_result = Cachex.set(state.cache, "my_key", 5)
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 5 })

    ttl_result = Cachex.ttl(state.cache, "my_key")
    assert(ttl_result == { :ok, nil })

    expire_result = Cachex.expire(state.cache, "my_key", :timer.seconds(5))
    assert(expire_result == { :ok, true })

    { status, ttl } = Cachex.ttl(state.cache, "my_key")
    assert(status == :ok)
    assert_in_delta(ttl, 5000, 5)
  end

  test "expire with an existing key and an existing ttl", state do
    set_result = Cachex.set(state.cache, "my_key", 5, ttl: :timer.seconds(10))
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 5 })

    { status, ttl } = Cachex.ttl(state.cache, "my_key")
    assert(status == :ok)
    assert_in_delta(ttl, 10000, 5)

    expire_result = Cachex.expire(state.cache, "my_key", :timer.seconds(5))
    assert(expire_result == { :ok, true })

    { status, ttl } = Cachex.ttl(state.cache, "my_key")
    assert(status == :ok)
    assert_in_delta(ttl, 5000, 5)
  end

  test "expire with a missing key", state do
    expire_result = Cachex.expire(state.cache, "my_key", :timer.seconds(5))
    assert(expire_result == { :missing, false })
  end

end
