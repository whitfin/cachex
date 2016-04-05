defmodule CachexTest.Debug do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "debug requires an existing cache name", _state do
    assert(Cachex.debug("test", &(&1)) == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "debug can track memory usage", state do
    { status, result } = Cachex.debug(state.cache, :memory_bytes)

    assert(status == :ok)
    assert_in_delta(result, 10600, 100)

    set_result = Cachex.set(state.cache, "key", "value")

    assert(set_result == { :ok, true })

    { status, result } = Cachex.debug(state.cache, :memory_bytes)

    assert(status == :ok)
    assert_in_delta(result, 10800, 100)
  end

  test "debug can track memory usage as a string", state do
    { status, result } = Cachex.debug(state.cache, :memory_str)

    assert(status == :ok)
    assert(String.starts_with?(result, "10.") && String.ends_with?(result, " KiB"))
  end

  test "debug can return an internal worker", state do
    { :ok, state_result  } = Cachex.debug(state.cache, :state)
    { :ok, worker_result } = Cachex.debug(state.cache, :worker)

    assert(state_result.__struct__ == Cachex.Worker)
    assert(worker_result.__struct__ == Cachex.Worker)
    assert(state_result == worker_result)
  end

  test "debug fails safely on invalid options", state do
    debug_result = Cachex.debug(state.cache, :missing_option)

    assert(debug_result == { :error, "Invalid debug option provided" })
  end

end
