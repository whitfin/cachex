defmodule Cachex.Set.RemoteTest do
  use PowerAssert, async: false

  setup do
    { :ok, cache: TestHelper.create_cache([remote: true]) }
  end

  test "key set", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_value" })
  end

  test "key set with existing key", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_value" })

    set_result = Cachex.set(state.cache, "my_key", "my_new_value")
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, "my_new_value" })
  end

  test "key set with expiration", state do
    set_result = Cachex.set(state.cache, "my_key", "my_value", ttl: :timer.seconds(5))
    assert(set_result == { :ok, true })

    { status, ttl } = Cachex.ttl(state.cache, "my_key")
    assert(status == :ok)
    assert_in_delta(ttl, 5000, 5)
  end

  test "key set with default expiration", _state do
    cache = TestHelper.create_cache([ default_ttl: :timer.seconds(5) ])

    set_result = Cachex.set(cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    { status, ttl } = Cachex.ttl(cache, "my_key")
    assert(status == :ok)
    assert_in_delta(ttl, 5000, 5)
  end

  test "key set with overridden default expiration", _state do
    cache = TestHelper.create_cache([ default_ttl: :timer.seconds(5) ])

    set_result = Cachex.set(cache, "my_key", "my_value", ttl: :timer.seconds(10))
    assert(set_result == { :ok, true })

    { status, ttl } = Cachex.ttl(cache, "my_key")
    assert(status == :ok)
    assert_in_delta(ttl, 10000, 5)
  end

end
