defmodule Cachex.Services.LocksmithTest do
  use CachexCase

  # This test verifies that we can detect when we're running inside a transactional
  # context within a process. This is used to automatically detect nested transactions
  # and should be false when run outside of the Locksmith server, otherwise true.
  test "detecting a transactional context" do
    # start a new cache
    cache = Helper.create_cache()

    # fetch the cache state
    state = Services.Overseer.retrieve(cache)

    # check transaction status from inside of a transaction
    transaction1 = Services.Locksmith.transaction(state, [], fn ->
      Services.Locksmith.transaction?()
    end)

    # check transaction status from outside of a transaction
    transaction2 = Services.Locksmith.transaction?()

    # the first should be true, latter be false
    assert(transaction1 == true)
    assert(transaction2 == false)
  end

  # When we execute a write against a key which isn't locked, we should bypass
  # the transaction context and write instantly. This is also the case for a cache
  # which has transactions disabled. This test will verify both of these cases to
  # ensure that writes are queued unnecessarily.
  test "executing a write outside of a transaction" do
    # start two caches, one transactional, one not
    cache1 = Helper.create_cache([ transactional:  true ])
    cache2 = Helper.create_cache([ transactional: false ])

    # fetch the states for the caches
    state1 = Services.Overseer.retrieve(cache1)
    state2 = Services.Overseer.retrieve(cache2)

    # our write action
    write = &Services.Locksmith.transaction?/0

    # execute writes against unlocked keys
    write1 = Services.Locksmith.write(state1, "key", write)
    write2 = Services.Locksmith.write(state2, "key", write)

    # neither should be transactional
    assert(write1 == false)
    assert(write2 == false)
  end

  # This test verifies the queueing of writes when operating against keys which
  # are currently locked. If a key is locked, the write should be submitted to the
  # lock server, to ensure consistency. However, if the state is not transactional,
  # this condition should never be checked. This test will verify both of these
  # cases in order to ensure that we're handling optimistic writes appropriately.
  # In addition this test also verifies the submission of a transaction in of
  # itself, as it's needed to test the write execution.
  test "executing a transactional block" do
    # start two caches, one transactional, one not
    cache1 = Helper.create_cache([ transactional: false ])
    cache2 = Helper.create_cache([ transactional:  true ])

    # fetch the states for the caches
    state1 = Services.Overseer.retrieve(cache1)
    state2 = Services.Overseer.retrieve(cache2)

    # our transaction actions - this will lock the key "key" in both caches for
    # 50ms before incrementing the same key by 1.
    transaction = fn(state) ->
      spawn(fn ->
        Services.Locksmith.transaction(state, [ "key" ], fn ->
          :timer.sleep(50)
          Cachex.incr(state, "key")
        end)
      end)
    end

    # execute transactions to lock our keys in the caches
    transaction.(state1)
    transaction.(state2)

    # wait for the spawns to happen
    :timer.sleep(10)

    # our write action - this will increment the key "key" by 1 and return the
    # value after incrementing as well as whether the write took place in a
    # transaction, this demonstrating the key locking.
    write = fn(state) ->
      Services.Locksmith.write(state, "key", fn ->
        {
          Cachex.incr!(state, "key"),
          Services.Locksmith.transaction?()
        }
      end)
    end

    # execute writes against unlocked keys
    write1 = write.(state1)
    write2 = write.(state2)

    # the first write executes before the transaction from outside
    assert(write1 == { 1, false })

    # the second write executes after the transaction from within
    assert(write2 == { 2, true })
  end

  # Because transactions execute inside a GenServer, we need to make sure the
  # server is able to withstand a crash inside the block (as blocks are totally
  # arbitrary). This test ensures that a crash does not cause an error, it just
  # notifies the user of the error occurring without causing other issues.
  test "executing a crashing transaction" do
    # create a test cache
    cache = Helper.create_cache([ transactions: true ])

    # retrieve the state for our cache
    state = Services.Overseer.retrieve(cache)

    # execute a crashing transaction
    result = Services.Locksmith.transaction(state, [ ], fn ->
      raise ArgumentError, message: "oh dear"
    end)

    # the result should contain the error
    assert(result == { :error, "oh dear" })
  end

  # Locking items should only be possible if the item is not already locked,
  # so we need to verify that this behaviour holds (otherwise we risk not
  # being covered in case of race conditions on locks).
  test "locking items in a table" do
    # create a test cache
    cache = Helper.create_cache()

    # retrieve the state for our cache
    state = Services.Overseer.retrieve(cache)

    # lock some keys in the cache
    true = Services.Locksmith.lock(state, [ "key1", "key2" ])

    # verify that both keys are now locked
    locked1 = Services.Locksmith.locked(state)
    assert(Enum.sort(locked1) == [ "key1", "key2" ])

    # locking the same keys should not work
    false = Services.Locksmith.lock(state, [ "key1" ])

    # verify that both keys are still locked
    locked2 = Services.Locksmith.locked(state)
    assert(Enum.sort(locked2) == [ "key1", "key2" ])

    # no keys should be locked if any are locked
    false = Services.Locksmith.lock(state, [ "key2", "key3" ])

    # verify that key3 was not added to the lock
    locked3 = Services.Locksmith.locked(state)
    assert(Enum.sort(locked3) == [ "key1", "key2" ])

    # unlock the second key
    true = Services.Locksmith.unlock(state, [ "key2" ])

    # verify that only one key is now locked
    locked4 = Services.Locksmith.locked(state)
    assert(Enum.sort(locked4) == [ "key1" ])

    # this call should now correctly lock both keys
    true = Services.Locksmith.lock(state, [ "key2", "key3" ])

    # verify that key3 was now added to the lock
    locked5 = Services.Locksmith.locked(state)
    assert(Enum.sort(locked5) == [ "key1", "key2", "key3" ])
  end

  # The Locksmith provides a `transactional/1` function to set the current
  # process as transactional. This test just makes sure that this sets the flag
  # correctly between true/false.
  test "setting a transactional context" do
    # check that the current process is unset
    is_transaction1 = Process.get(:cachex_transaction)

    # ensure unsert
    assert(is_transaction1 == nil)

    # set the value to true
    Services.Locksmith.start_transaction()

    # check that the current process is true
    is_transaction2 = Process.get(:cachex_transaction)

    # ensure set to true
    assert(is_transaction2 == true)

    # set the value to false
    Services.Locksmith.stop_transaction()

    # check that the current process is false
    is_transaction3 = Process.get(:cachex_transaction)

    # ensure set to false
    assert(is_transaction3 == false)
  end
end
