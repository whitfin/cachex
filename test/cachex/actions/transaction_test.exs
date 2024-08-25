defmodule Cachex.Actions.TransactionTest do
  use CachexCase

  # This test ensures that a transaction will block any write operations on the
  # same keys by ensuring the the transaction has executed completely before any
  # new operations. To ensure that this is the case, we sleep inside a transaction
  # which blocks the increment outside. The increment happens whilst there is still
  # 40ms left in the sleep inside the transaction, but it returns 2 - meaning that
  # it was queued until after the transaction had finished sleeping and written
  # the value for the first time.
  test "executing a transaction is atomic" do
    # create a test cache
    cache = Helper.create_cache(transactions: true)

    # spawn a transaction to increment a key
    spawn(fn ->
      Cachex.transaction(cache, ["key"], fn state ->
        :timer.sleep(50)
        Cachex.incr(state, "key")
      end)
    end)

    # wait for the spawns to happen
    :timer.sleep(10)

    # write a key from outside a transaction
    incr = Cachex.incr(cache, "key")

    # verify the write was queued after the transaction
    assert(incr == {:ok, 2})
  end

  # This test ensures that any errors which occur inside a transaction are caught
  # and an error status is returned instead of crashing the transaction server.
  test "raising errors from inside transactions" do
    # create a test cache
    cache = Helper.create_cache()

    # execute a broken transaction
    result1 =
      Cachex.transaction(cache, [], fn ->
        raise ArgumentError, message: "Error message"
      end)

    # verify the error was caught
    assert(result1 == {:error, "Error message"})

    # ensure a new transaction executes normally
    result2 =
      Cachex.transaction(cache, [], fn ->
        Cachex.Services.Locksmith.transaction?()
      end)

    # verify the results are correct
    assert(result2 == {:ok, true})
  end

  # This test makes sure that a cache with transactions disabled will automatically
  # enable them the first time a transaction is executed. Simple enough to test;
  # create a state without transactions, call a transaction, and then it should
  # have transactions enabled from that point onwards.
  test "transactions become enabled automatically" do
    # create a test cache
    cache = Helper.create_cache()

    # retrieve the cache state
    state1 = Services.Overseer.retrieve(cache)

    # verify transactions are disabled
    assert(cache(state1, :transactions) == false)

    # execute a transactions
    Cachex.transaction(cache, [], & &1)

    # pull the state back from the cache again
    state2 = Services.Overseer.retrieve(cache)

    # verify transactions are now enabled
    assert(cache(state2, :transactions) == true)
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "transactions inside a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes} = Helper.create_cache_cluster(2)

    # we know that 2 & 3 hash to the same slots
    {:ok, result} = Cachex.transaction(cache, [], &:erlang.phash2/1)
    {:ok, ^result} = Cachex.transaction(cache, [2, 3], &:erlang.phash2/1)

    # check the result phashed ok
    assert(result > 0 && is_integer(result))
  end

  # This test verifies that all keys in a put_many/3 must hash to the
  # same slot in a cluster, otherwise a cross_slot error will occur.
  @tag distributed: true
  test "multiple slots will return a :cross_slot error" do
    # create a new cache cluster for cleaning
    {cache, _nodes} = Helper.create_cache_cluster(2)

    # we know that 1 & 3 don't hash to the same slots
    transaction = Cachex.transaction(cache, [1, 2], &:erlang.phash2/1)

    # so there should be an error
    assert(transaction == {:error, :cross_slot})
  end
end
