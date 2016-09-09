defmodule Cachex.Actions.PersistTest do
  use PowerAssert, async: false

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "persist requires an existing cache name", _state do
    assert(Cachex.persist("test", "key") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "persist with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.persist(state_result, "key") == { :missing, false })
  end

  test "persist with a key with no ttl", state do
    set_result = Cachex.set(state.cache, "my_key", 5)
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 5 })

    persist_result = Cachex.persist(state.cache, "my_key")
    assert(persist_result == { :ok, true })

    ttl_result = Cachex.ttl(state.cache, "my_key")
    assert(ttl_result == { :ok, nil })
  end

  test "persist with a key with a ttl", state do
    set_result = Cachex.set(state.cache, "my_key", 5, ttl: :timer.seconds(5))
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 5 })

    { status, ttl } = Cachex.ttl(state.cache, "my_key")
    assert(status == :ok)
    assert_in_delta(ttl, 5000, 5)

    persist_result = Cachex.persist(state.cache, "my_key")
    assert(persist_result == { :ok, true })

    ttl_result = Cachex.ttl(state.cache, "my_key")
    assert(ttl_result == { :ok, nil })
  end

  test "persist with a missing key", state do
    persist_result = Cachex.persist(state.cache, "my_key")
    assert(persist_result == { :missing, false })
  end

end
