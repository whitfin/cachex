defmodule Cachex.ActionsTest do
  use CachexCase

  # for our Action macros
  import Cachex.Actions

  test "carrying out generic read actions" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = Helper.create_cache([ hooks: [ hook ] ])

    # retrieve the state
    state = Services.Overseer.retrieve(cache)

    # write several values
    { :ok, true } = Cachex.set(cache, 1, 1)
    { :ok, true } = Cachex.set(cache, 2, 2, ttl: 1)

    # let the TTL expire
    :timer.sleep(2)

    # read back the values from the table
    record1 = Cachex.Actions.read(state, 1)
    record2 = Cachex.Actions.read(state, 2)
    record3 = Cachex.Actions.read(state, 3)

    # the first should find a record
    assert(match?({ :entry, 1, _touched, nil, 1 }, record1))

    # the second should expire
    assert(record2 == nil)

    # the third is missing
    assert(record3 == nil)

    # we should receive the purge of the second key
    assert_receive({ { :purge, [[]] }, { :ok, 1 } })

    # verify if the second key exists
    exists1 = Cachex.exists?(cache, 2)

    # it shouldn't exist
    assert(exists1 == { :ok, false })
  end

  test "carrying out generic write actions" do
    # create a test cache
    cache = Helper.create_cache()

    # retrieve the state
    state = Services.Overseer.retrieve(cache)

    # write some values into the cache
    write1 = Cachex.Actions.write(state, entry(
      key: "key",
      touched: 1,
      value: "value"
    ))

    # verify the write
    assert(write1 == { :ok, true })

    # retrieve the value
    value1 = Cachex.Actions.read(state, "key")

    # validate the value
    assert(value1 == entry(
      key: "key",
      touched: 1,
      value: "value"
    ))

    # attempt to update some values
    update1 = Cachex.Actions.update(state, "key", entry_mod(value: "yek"))
    update2 = Cachex.Actions.update(state, "nop", entry_mod(value: "yek"))

    # the first should be ok
    assert(update1 == { :ok, true })

    # the second is missing
    assert(update2 == { :missing, false })

    # retrieve the value
    value2 = Cachex.Actions.read(state, "key")

    # validate the update took effect
    assert(value2 == entry(
      key: "key",
      touched: 1,
      value: "yek"
    ))
  end

  # This test focuses on the `defact` macro which binds Hook notifications to the
  # Action interface. We just ensure that hooks are sent to both types of hook
  # appropriately and with the correct messages.
  test "executing actions inside a notify scope" do
    # define a pre hook
    hook1 = ForwardHook.create(type: :pre)

    # define a post hook
    hook2 = ForwardHook.create(type: :post)

    # create a cache for each hook
    cache1 = Helper.create_cache([ hooks: [ hook1 ] ])
    cache2 = Helper.create_cache([ hooks: [ hook2 ] ])

    # get the states for each cache
    state1 = Services.Overseer.retrieve(cache1)
    state2 = Services.Overseer.retrieve(cache2)

    # execute some actions
    5  = execute(state1, 5, [])
    10 = execute(state1, 10, [ via: { :fake, [[]] } ])
    15 = execute(state1, 15, [ notify: false ])

    # check the messages arrive
    assert_receive({ { :test, [ 5, []] }, nil })
    assert_receive({ { :fake, [[]] }, nil })

    # ensure the last doesn't
    refute_receive({ :test, [15, [ notify: false ] ] })

    # execute some actions
    5  = execute(state2, 5, [])
    10 = execute(state2, 10, [ via: { :fake, [[]] } ])
    15 = execute(state2, 15, [ notify: false ])

    # check the messages arrive
    assert_receive({ { :test, [ 5, []] }, 5 })
    assert_receive({ { :fake, [[]] }, 10 })

    # ensure the last doesn't
    refute_receive({ { :test, [15, [ notify: false ] ] }, 15 })
  end

  # Use our actions Macro internally as a test example for scoping.
  defaction test(cache, value, options),
    do: value

  # This test just ensures that we correctly convert return values to either a
  # :commit Tuple or an :ignore Tuple. We also make sure to verify that the default
  # behaviour is a :commit Tuple for backwards compatibility.
  test "normalizing commit/ignore return values" do
    # define our base Tuples to test against
    tuple1 = { :commit, true }
    tuple2 = { :ignore, true }
    tuple3 = { :error,  true }

    # define our base value
    value1 = true

    # normalize all values
    result1 = Cachex.Actions.normalize_commit(tuple1)
    result2 = Cachex.Actions.normalize_commit(tuple2)
    result3 = Cachex.Actions.normalize_commit(tuple3)
    result4 = Cachex.Actions.normalize_commit(value1)

    # the first three should persist
    assert(result1 == tuple1)
    assert(result2 == tuple2)
    assert(result3 == tuple3)

    # the value should be converted to the first
    assert(result4 == tuple1)
  end

  # This test just provides basic coverage of the write_mod function, by using
  # tags to determine the correct Action to use to write a value. We make sure
  # that the :missing and :new tags define a Set and the others define an Update.
  test "retrieving a module name to write with" do
    # ask for some modules
    result1 = Cachex.Actions.write_mod(:new)
    result2 = Cachex.Actions.write_mod(:missing)
    result3 = Cachex.Actions.write_mod(:unknown)

    # the first two should be Set actions
    assert(result1 == Cachex.Actions.Set)
    assert(result2 == Cachex.Actions.Set)

    # the third should be an Update
    assert(result3 == Cachex.Actions.Update)
  end
end
