defmodule Cachex.ActionsTest do
  use CachexCase

  test "carrying out generic read actions" do
    # create a forwarding hook
    hook = ForwardHook.create(%{ results: true })

    # create a test cache
    cache = Helper.create_cache([ hooks: [ hook ] ])

    # retrieve the state
    state = Cachex.State.get(cache)

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
    assert(match?({ 1, _touched, nil, 1 }, record1))

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
    state = Cachex.State.get(cache)

    # write some values into the cache
    write1 = Cachex.Actions.write(state, { "key", 1, nil, "value" })

    # verify the write
    assert(write1 == { :ok, true })

    # retrieve the value
    value1 = Cachex.Actions.read(state, "key")

    # validate the value
    assert(value1 == { "key", 1, nil, "value" })

    # attempt to update some values
    update1 = Cachex.Actions.update(state, "key", [{ 4, "yek" }])
    update2 = Cachex.Actions.update(state, "nop", [{ 4, "yek" }])

    # the first should be ok
    assert(update1 == { :ok, true })

    # the second is missing
    assert(update2 == { :missing, false })

    # retrieve the value
    value2 = Cachex.Actions.read(state, "key")

    # validate the update took effect
    assert(value2 == { "key", 1, nil, "yek" })
  end

  test "executing actions inside a notify scope" do
    # define a pre hook
    hook1 = ForwardHook.create(%{ type: :pre })

    # define a post hook
    hook2 = ForwardHook.create(%{ type: :post, results: true })

    # create a cache for each hook
    cache1 = Helper.create_cache([ hooks: [ hook1 ] ])
    cache2 = Helper.create_cache([ hooks: [ hook2 ] ])

    # get the states for each cache
    state1 = Cachex.State.get(cache1)
    state2 = Cachex.State.get(cache2)

    # execute some actions
    5  = Cachex.Actions.do_action(state1, { :fake, [ [ ] ] }, fn -> 5 end)
    10 = Cachex.Actions.do_action(state1, { :fake, [ [ via: { :test, [[]] } ] ] }, fn -> 10 end)
    15 = Cachex.Actions.do_action(state1, { :fake, [ [ notify: false ] ] }, fn -> 15 end)

    # check the messages arrive
    assert_receive({ :fake, [[]] })
    assert_receive({ :test, [[]] })

    # ensure the last doesn't
    refute_receive({ :fake, [ [ notify: false ] ] })

    # execute some actions
    5  = Cachex.Actions.do_action(state2, { :fake, [ [ ] ] }, fn -> 5 end)
    10 = Cachex.Actions.do_action(state2, { :fake, [ [ via: { :test, [[]] } ] ] }, fn -> 10 end)
    15 = Cachex.Actions.do_action(state2, { :fake, [ [ notify: false ] ] }, fn -> 15 end)

    # check the messages arrive
    assert_receive({ { :fake, [[]] }, 5 })
    assert_receive({ { :test, [[]] }, 10 })

    # ensure the last doesn't
    refute_receive({ { :fake, [ [ notify: false ] ] }, 15 })
  end

end
