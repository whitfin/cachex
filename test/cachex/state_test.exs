defmodule Cachex.StateTest do
  use CachexCase

  # This test case just covers the addition of a new state into the state table.
  # We also cover removal just to avoid duplicating a lot of test code again.
  test "adding and removing state in the table" do
    # grab a state name
    name = Helper.create_name()

    # create our state
    state = %Cachex.State{ cache: name }

    # set our state in the table
    Cachex.State.set(name, state)

    # ensure that the state exists
    assert(Cachex.State.member?(name))

    # remove our state from the table
    Cachex.State.del(name)

    # ensure the state is gone
    refute(Cachex.State.member?(name))
  end

  # Covers the retrieval of a cache state from inside the table. We just have to
  # make sure that the returned cache value is the same as what went into the
  # table in the first place.
  test "retrieving a state from the table" do
    # grab a state name
    name = Helper.create_name()

    # create our state
    state = %Cachex.State{ cache: name }

    # set our state in the table
    Cachex.State.set(name, state)

    # pull back the state from the table
    result = Cachex.State.get(name)

    # ensure nothing has changed
    assert(result == state)
  end

  # Updates to a state should always be sequential, and so we have a custom update
  # function with a transaction to ensure that the state is modified consistently.
  # This test ensures that these updates take place correctly and sequentially.
  # In addition, we make sure that updates are triggered against hooks to ensure
  # that provisioned hooks receive the new state they're working with.
  test "updating a state in the table" do
    # create a hook listener
    hook = ForwardHook.create(%{
      provide: [ :worker ]
    })

    # start up our cache using the helper
    name = Helper.create_cache([ hooks: hook ])

    # retrieve our state
    state = Cachex.State.get(name)

    # store our updated states
    update1 = %Cachex.State{ state | default_ttl: 5 }
    update2 = %Cachex.State{ state | default_ttl: 3 }

    # update in parallel with a wait to make sure that writes block and always
    # execute in sequence, regardless of when they actually update
    spawn(fn ->
      Cachex.State.update(name, fn(_) ->
        :timer.sleep(25)
        update1
      end)
    end)

    # make sure we execute second
    :timer.sleep(5)

    # begin to update our state in advance of the spawned process
    Cachex.State.update(name, fn(_) ->
      update2
    end)

    # wait until done
    :timer.sleep(50)

    # pull back the state from the table
    result = Cachex.State.get(name)

    # ensure the last call is the new value
    assert(result.default_ttl == 3)

    # now we need to make sure our state was forwarded
    assert_receive({ :provision, { :worker, ^update2 } })
  end

  # Because the updates execute inside an Agent, we need to make sure that we
  # don't just crash on an error when updating the state. This test will just
  # ensure that raised errors are caught successfully and don't cause a bad state
  # inside the state table.
  test "updating a state catches errors" do
    # grab a state name
    name = Helper.create_name()

    # create our state
    state = %Cachex.State{ cache: name }

    # set our state in the table
    Cachex.State.set(name, state)

    # ensure that the state exists
    assert(Cachex.State.member?(name))

    # begin a bad update on the table
    Cachex.State.update(name, fn(_) ->
      raise ArgumentError
    end)

    # pull back the state from the table
    result = Cachex.State.get(name)

    # ensure that the state has persisted
    assert(result == state)
  end

end
