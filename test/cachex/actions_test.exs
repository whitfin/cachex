defmodule Cachex.ActionsTest do
  use CachexCase

  # for our Action macros
  import Cachex.Actions

  test "carrying out generic read actions" do
    # create a forwarding hook
    hook = ForwardHook.create(%{ results: true })

    # create a test cache
    cache = Helper.create_cache([ hooks: [ hook ] ])

    # retrieve the state
    state = Services.Overseer.get(cache)

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
    state = Services.Overseer.get(cache)

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
    hook1 = ForwardHook.create(%{ type: :pre })

    # define a post hook
    hook2 = ForwardHook.create(%{ type: :post })

    # create a cache for each hook
    cache1 = Helper.create_cache([ hooks: [ hook1 ] ])
    cache2 = Helper.create_cache([ hooks: [ hook2 ] ])

    # get the states for each cache
    state1 = Services.Overseer.get(cache1)
    state2 = Services.Overseer.get(cache2)

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
end
