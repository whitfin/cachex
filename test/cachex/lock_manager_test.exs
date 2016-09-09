defmodule Cachex.LockManagerTest do
  use PowerAssert, async: false

  alias Cachex.LockManager
  alias Cachex.State

  setup do
    { :ok, cache: State.get(TestHelper.create_cache([ transactions: false ])) }
  end

  test "checking for a transaction", state do
    refute(LockManager.is_transaction())

    LockManager.transaction(state.cache, [], fn ->
      assert(LockManager.is_transaction())
    end)
  end

  test "writes execute outside of transactions when disabled", state do
    LockManager.write(state.cache, "key", fn ->
      refute(LockManager.is_transaction())
    end)
  end

  test "writes execute when keys are not locked by transactions", state do
    enabled_cache = %State{ state.cache | transactions: true }

    LockManager.write(enabled_cache, "key", fn ->
      refute(LockManager.is_transaction())
    end)
  end

  test "writes queue after transactions when keys are locked", state do
    enabled_cache = %State{ state.cache | transactions: true }

    spawn(fn ->
      LockManager.transaction(enabled_cache, [ "test" ], fn ->
        Cachex.incr(enabled_cache, "test")
        :timer.sleep(1000)
      end)
    end)

    :timer.sleep(5)

    incr_result = LockManager.write(enabled_cache, "key", fn ->
      Cachex.incr(enabled_cache, "test")
    end)

    assert(incr_result == { :ok, 2 })
  end

  test "error catching inside a transaction", state do
    result = LockManager.transaction(state.cache, [ "key" ], fn ->
      raise ArgumentError, message: "oh dear"
    end)

    assert(result == { :error, "oh dear" })
  end

end
