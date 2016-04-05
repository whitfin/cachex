defmodule CachexTest.Transaction do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "transaction requires an existing cache name", _state do
    assert(Cachex.transaction("test", &(&1)) == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "transaction requires a single arity function", state do
    worker = Cachex.debug!(state.cache, :state)

    assert_raise(FunctionClauseError, fn ->
      Cachex.Worker.transaction(worker, "test")
    end)

    assert_raise(FunctionClauseError, fn ->
      Cachex.Worker.transaction(worker, fn(_, _) -> true end)
    end)
  end

  test "transaction carries out many actions", state do
    result = Cachex.transaction(state.cache, fn(worker) ->
      Cachex.set(worker, "my_key1", "my_value1")
      Cachex.set(worker, "my_key2", "my_value2")
      Cachex.set(worker, "my_key3", "my_value3")
    end)

    assert(result == { :ok, { :ok, true } })

    size_result = Cachex.size(state.cache)

    assert(size_result == { :ok, 3 })
  end

  test "transaction returns a custom value", state do
    transaction_result = Cachex.transaction(state.cache, fn(worker) ->
      Cachex.get(worker, "my_key")
    end)

    assert(transaction_result == { :ok, { :missing, nil } })
  end

  test "transaction can exit if `abort/3` is called", state do
    transaction_result = Cachex.transaction(state.cache, fn(worker) ->
      Cachex.set(worker, "my_key", "my_value")
      Cachex.abort(worker, :exit_early)
    end)

    assert(transaction_result == { :error, :exit_early })

    get_result = Cachex.get(state.cache, "my_key")

    assert(get_result == { :missing, nil })
  end

  test "transaction with async is faster than non-async", state do
    { async_time, _res } = :timer.tc(fn ->
      Cachex.transaction(state.cache, fn(worker) ->
        Cachex.set(worker, "my_key1", "my_value1")
      end, async: true)
    end)

    { sync_time, _res } = :timer.tc(fn ->
      Cachex.transaction(state.cache, fn(worker) ->
        Cachex.set(worker, "my_key2", "my_value2")
      end, async: false)
    end)

    get_result = Cachex.get(state.cache, "my_key1")
    assert(get_result == { :ok, "my_value1" })
    assert(async_time < sync_time / 2)
  end

end
