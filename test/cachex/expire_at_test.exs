defmodule CachexTest.ExpireAt do
  use PowerAssert, async: false

  alias Cachex.Util

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "expire at requires an existing cache name", _state do
    assert(Cachex.expire_at("test", "key", Util.now()) == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "expire at with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.expire_at(state_result, "key", Util.now() + 5) == { :missing, false })
  end

  test "expire at with an existing key and no ttl", state do
    set_result = Cachex.set(state.cache, "my_key", 5)
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 5 })

    ttl_result = Cachex.ttl(state.cache, "my_key")
    assert(ttl_result == { :ok, nil })

    expire_at_result = Cachex.expire_at(state.cache, "my_key", Util.now() + :timer.seconds(5))
    assert(expire_at_result == { :ok, true })

    { status, ttl } = Cachex.ttl(state.cache, "my_key")
    assert(status == :ok)
    assert_in_delta(ttl, 5000, 5)
  end

  test "expire_at with an existing key and an existing ttl", state do
    set_result = Cachex.set(state.cache, "my_key", 5, ttl: :timer.seconds(10))
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 5 })

    { status, ttl } = Cachex.ttl(state.cache, "my_key")
    assert(status == :ok)
    assert_in_delta(ttl, 10000, 5)

    expire_at_result = Cachex.expire_at(state.cache, "my_key", Util.now() + :timer.seconds(5))
    assert(expire_at_result == { :ok, true })

    { status, ttl } = Cachex.ttl(state.cache, "my_key")
    assert(status == :ok)
    assert_in_delta(ttl, 5000, 5)
  end

  test "expire_at with a missing key", state do
    expire_at_result = Cachex.expire_at(state.cache, "my_key", Util.now() + :timer.seconds(5))
    assert(expire_at_result == { :missing, false })
  end

  test "expire_at with an already passed timestamp", state do
    set_result = Cachex.set(state.cache, "my_key", 5)
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 5 })

    expire_at_result = Cachex.expire_at(state.cache, "my_key", Util.now() - :timer.seconds(1))
    assert(expire_at_result == { :ok, true })
  end

end
