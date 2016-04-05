defmodule CachexTest.Execute do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "execute requires an existing cache name", _state do
    assert(Cachex.execute("test", &(&1)) == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "execute carries out many actions", state do
    result = Cachex.execute(state.cache, fn(worker) ->
      Cachex.set(worker, "my_key1", "my_value1")
      Cachex.set(worker, "my_key2", "my_value2")
      Cachex.set(worker, "my_key3", "my_value3")
    end)

    assert(result == { :ok, { :ok, true } })

    size_result = Cachex.size(state.cache)

    assert(size_result == { :ok, 3 })
  end

  test "execute requires a single arity function", state do
    worker = Cachex.debug!(state.cache, :state)

    assert_raise(FunctionClauseError, fn ->
      Cachex.Worker.execute(worker, "test")
    end)

    assert_raise(FunctionClauseError, fn ->
      Cachex.Worker.execute(worker, fn(_, _) -> true end)
    end)
  end

  test "execute returns a custom value", state do
    execute_result = Cachex.execute(state.cache, fn(worker) ->
      Cachex.get(worker, "my_key")
    end)

    assert(execute_result == { :ok, { :missing, nil } })
  end

  test "execute with async is faster than non-async", state do
    { async_time, _res } = :timer.tc(fn ->
      Cachex.execute(state.cache, fn(worker) ->
        Cachex.set(worker, "my_key1", "my_value1")
      end, async: true)
    end)

    { sync_time, _res } = :timer.tc(fn ->
      Cachex.execute(state.cache, fn(worker) ->
        Cachex.set(worker, "my_key2", "my_value2")
      end, async: false)
    end)

    get_result = Cachex.get(state.cache, "my_key1")
    assert(get_result == { :ok, "my_value1" })
    assert(async_time < sync_time / 2)
  end

end
