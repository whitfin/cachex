defmodule Cachex.ExecuteTest do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "execute requires an existing cache name", _state do
    assert(Cachex.execute("test", &(&1)) == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "execute with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.execute(state_result, &(!!&1)) == { :ok, true })
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
    worker = Cachex.inspect!(state.cache, :state)

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

end
