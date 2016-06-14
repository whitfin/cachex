defmodule Cachex.TransactionTest do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "transaction requires an existing cache name", _state do
    assert(Cachex.transaction("test", &(&1)) == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "transaction with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.transaction(state_result, &(!!&1)) == { :ok, true })
  end

  test "transaction requires a single arity function", state do
    worker = Cachex.inspect!(state.cache, :state)

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

end
