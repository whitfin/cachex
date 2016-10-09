defmodule Cachex.Actions.InvokeTest do
  use CachexCase

  # This test covers the ability to run commands tagged with the `:modify` type.
  # We test that we can return our own values whilst modifying Lists. There is
  # also coverage here for checking that the same value is not written to the
  # cache if it remains unchanged - but this can only be seen using coverage tools
  # due to the nature of the backing writes.
  test "invoking :modify commands" do
    # create a test cache
    cache = Helper.create_cache([
      commands: [
        lpop: { :modify, &lpop/1 },
        rpop: { :modify, &rpop/1 }
      ]
    ])

    # set a list inside the cache
    { :ok, true } = Cachex.set(cache, "list", [ 1, 2, 3, 4 ])

    # retrieve the raw record
    { "list", touched, nil, _val } = Cachex.inspect!(cache, { :record, "list" })

    # execute some custom commands
    lpop1 = Cachex.invoke(cache, "list", :lpop)
    lpop2 = Cachex.invoke(cache, "list", :lpop)
    rpop1 = Cachex.invoke(cache, "list", :rpop)
    rpop2 = Cachex.invoke(cache, "list", :rpop)

    # verify that all results are as expected
    assert(lpop1 == { :ok, 1 })
    assert(lpop2 == { :ok, 2 })
    assert(rpop1 == { :ok, 4 })
    assert(rpop2 == { :ok, 3 })

    # retrieve the raw record again
    inspect1 = Cachex.inspect!(cache, { :record, "list" })

    # verify the touched time was unchanged
    assert(inspect1 == { "list", touched, nil, [ ] })

    # pop some extras to test avoiding writes
    lpop3 = Cachex.invoke(cache, "list", :lpop)
    rpop3 = Cachex.invoke(cache, "list", :rpop)

    # verify we stayed the same
    assert(lpop3 == { :ok, nil })
    assert(rpop3 == { :ok, nil })
  end

  # This test covers the ability to run commands tagged with the `:return type.
  # We simply test that we can return values as expected, as this is a very simple
  # implementation which doesn't have much room for error beyond user-created issues.
  test "invoking :return commands" do
    # create a test cache
    cache = Helper.create_cache([
      commands: [
        last: { :return, &List.last/1 }
      ]
    ])

    # define a validation function
    validate = fn(list, expected) ->
      # set a list inside the cache
      { :ok, true } = Cachex.set(cache, "list", list)

      # retrieve the last value
      last = Cachex.invoke(cache, "list", :last)

      # compare with the expected
      assert(last == { :ok, expected })
    end

    # ensure basic list works
    validate.([ 1, 2, 3, 4, 5 ], 5)
    validate.([ 1 ], 1)

    # ensure empty list works
    validate.([ ], nil)
  end

  # This test just makes sure that we correctly return an error in case the called
  # function is not a valid cache function. We make sure that missing functions
  # fail, as well as commands which have been badly formed due to arity or tag.
  test "invoking invalid commands" do
    # create a test cache
    cache = Helper.create_cache()

    # retrieve the state
    state = Cachex.State.get(cache)

    # modify the state to have fake commands
    state = %Cachex.State{ state | commands: %{
      fake_mod: { :modify, &({ &1, &2 }) },
      fake_ret: { :return, &({ &1, &2 }) }
    } }

    # try to invoke a missing command
    invoke1 = Cachex.invoke(state, "heh", :unknowns)

    # try to invoke bad arity commands
    invoke2 = Cachex.invoke(state, "heh", :fake_mod)
    invoke3 = Cachex.invoke(state, "heh", :fake_ret)

    # all should error
    assert(invoke1 == { :error, :invalid_command })
    assert(invoke2 == { :error, :invalid_command })
    assert(invoke3 == { :error, :invalid_command })
  end

  # A simple left pop for a List to remove the head and return the tail as the
  # modified list. This functions assumes the value is always a List.
  defp lpop([ head | tail ]),
    do: { head, tail }
  defp lpop([ ] = list),
    do: {  nil, list }

  # A simple right pop for a List to remove the rightmost value and return the
  # rest as a modified list. This functions assumes the value is always a List.
  defp rpop([ _head | _tail ] = list),
    do: { List.last(list), :lists.droplast(list) }
  defp rpop([ ] = list),
    do: { nil, list }

end
