defmodule Cachex.Refresh.LocalTest do
  use PowerAssert, async: false

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "refresh with an existing key and no ttl", state do
    set_result = Cachex.set(state.cache, "my_key", 5)
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 5 })

    ttl_result = Cachex.ttl(state.cache, "my_key")
    assert(ttl_result == { :ok, nil })

    refresh_result = Cachex.refresh(state.cache, "my_key")
    assert(refresh_result == { :ok, true })

    ttl_result = Cachex.ttl(state.cache, "my_key")
    assert(ttl_result == { :ok, nil })
  end

  test "refresh with an existing key and an existing ttl", state do
    set_result = Cachex.set(state.cache, "my_key", 5, ttl: :timer.seconds(1))
    assert(set_result == { :ok, true })

    get_result = Cachex.get(state.cache, "my_key")
    assert(get_result == { :ok, 5 })

    :timer.sleep(100)

    { status, ttl } = Cachex.ttl(state.cache, "my_key")
    assert(status == :ok)
    assert(ttl < 901)

    refresh_result = Cachex.refresh(state.cache, "my_key")
    assert(refresh_result == { :ok, true })

    { status, ttl } = Cachex.ttl(state.cache, "my_key")
    assert(status == :ok)
    assert_in_delta(ttl, 1000, 5)
  end

  test "refresh with a missing key", state do
    refresh_result = Cachex.refresh(state.cache, "my_key")
    assert(refresh_result == { :missing, false })
  end

end
