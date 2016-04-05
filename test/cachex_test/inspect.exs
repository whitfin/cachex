defmodule CachexTest.Inspect do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "inspect requires an existing cache name", _state do
    assert(Cachex.inspect("test", &(&1)) == { :error, "Invalid cache provided, got: \"test\"" })
    assert(Cachex.Inspector.inspect("test", "test") == { :error, "Invalid cache reference provided" })
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
    { status1, default_result } = Cachex.inspect(state.cache, :memory)
    { status2, result } = Cachex.inspect(state.cache, { :memory, :bytes })

    assert(status1 == :ok)
    assert(status2 == :ok)
    assert(default_result == result)
    assert_in_delta(result, 10600, 100)

    set_result = Cachex.set(state.cache, "key", "value")

    assert(set_result == { :ok, true })

    { status, result } = Cachex.inspect(state.cache, { :memory, :bytes })

    assert(status == :ok)
    assert_in_delta(result, 10800, 100)
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

  test "inspect fails safely on invalid options", state do
    inspect_result = Cachex.inspect(state.cache, :missing_option)

    assert(inspect_result == { :error, "Invalid inspect option provided" })
  end

end
