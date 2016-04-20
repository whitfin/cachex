defmodule CachexTest.Inspect do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "inspect requires an existing cache name", _state do
    assert(Cachex.inspect("test", &(&1)) == { :error, "Invalid cache provided, got: \"test\"" })
    assert(Cachex.Inspector.inspect("test", "test") == { :error, "Invalid cache reference provided" })
  end

  test "inspect with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.inspect(state_result, :worker) == { :ok, state_result })
  end

  test "inspect requires a valid option", state do
    assert(Cachex.inspect(state.cache, "failed") == { :error, "Invalid inspect option provided" })
  end

  test "inspect functions with a worker state", state do
    { :ok, state_result } = Cachex.inspect(state.cache, :state)
    { :ok, worker_result } = Cachex.inspect(state_result, :worker)

    assert(state_result.__struct__ == Cachex.Worker)
    assert(worker_result.__struct__ == Cachex.Worker)
    assert(state_result == worker_result)
  end

  test "inspect can track memory usage", state do
    { status, result } = Cachex.inspect(state.cache, { :memory, :bytes })

    assert(status == :ok)
    assert_in_delta(result, 10600, 100)

    set_result = Cachex.set(state.cache, "key", "value")

    assert(set_result == { :ok, true })

    { status, result } = Cachex.inspect(state.cache, { :memory, :bytes })

    assert(status == :ok)
    assert_in_delta(result, 10800, 100)
  end

  test "inspect can track the last run of a Janitor", state do
    cache = TestHelper.create_cache(default_ttl: 1, ttl_interval: 100)
    start = Cachex.Util.now()

    set_result = Cachex.set(cache, "key", "value")
    assert(set_result == { :ok, true })

    :timer.sleep(101)

    { status, inspection } = Cachex.inspect(cache, { :janitor, :last })

    assert(status == :ok)
    assert(inspection.count == 1)
    assert(inspection.duration < 75)
    assert_in_delta(inspection.started, start + 100, 10)

    inspect_result = Cachex.inspect(state.cache, { :janitor, :last })
    assert(inspect_result == { :error, "Janitor not running for cache #{inspect(state.cache)}" })
  end

  test "inspect can track memory usage as a string", state do
    { status, result } = Cachex.inspect(state.cache, { :memory, :binary })

    assert(status == :ok)
    assert(String.starts_with?(result, "10.") && String.ends_with?(result, " KiB"))
  end

  test "inspect can error when asked for invalid memory types", state do
    inspect_result = Cachex.inspect(state.cache, { :memory, :yolo })

    assert(inspect_result == { :error, "Invalid memory inspection type provided" })
  end

  test "inspect can return an internal worker", state do
    { :ok, state_result  } = Cachex.inspect(state.cache, :state)
    { :ok, worker_result } = Cachex.inspect(state.cache, :worker)

    assert(state_result.__struct__ == Cachex.Worker)
    assert(worker_result.__struct__ == Cachex.Worker)
    assert(state_result == worker_result)
  end

  test "inspect can return a count of expired keys", state do
    inspect_result = Cachex.inspect(state.cache, { :expired, :count })
    assert(inspect_result == { :ok, 0 })

    set_result = Cachex.set(state.cache, "key", "value", ttl: 1)
    assert(set_result == { :ok, true })

    :timer.sleep(2)

    inspect_result = Cachex.inspect(state.cache, { :expired, :count })
    assert(inspect_result == { :ok, 1 })

    inspect_result = Cachex.inspect(state.cache, { :expired, :keys })
    assert(inspect_result == { :ok, [ "key" ] })

    inspect_result = Cachex.inspect(state.cache, { :expired, :missing })
    assert(inspect_result == { :error, "Invalid expiration inspection type provided" })
  end

  test "inspect fails safely on invalid options", state do
    inspect_result = Cachex.inspect(state.cache, :missing_option)

    assert(inspect_result == { :error, "Invalid inspect option provided" })
  end

end
