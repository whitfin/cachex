defmodule Cachex.Actions.InvokeTest do
  use Cachex.Test.Case

  # This test covers the ability to run commands tagged with the `:modify` type.
  # We test that we can return our own values whilst modifying Lists. There is
  # also coverage here for checking that the same value is not written to the
  # cache if it remains unchanged - but this can only be seen using coverage tools
  # due to the nature of the backing writes.
  test "invoking :write commands" do
    # create a test cache
    cache =
      TestUtils.create_cache(
        commands: [
          lpop: command(type: :write, execute: &lpop/1),
          rpop: command(type: :write, execute: &rpop/1)
        ]
      )

    # set a list inside the cache
    {:ok, true} = Cachex.put(cache, "list", [1, 2, 3, 4])

    # retrieve the raw record
    entry(key: "list", modified: modified) =
      Cachex.inspect!(cache, {:entry, "list"})

    # execute some custom commands
    lpop1 = Cachex.invoke(cache, :lpop, "list")
    lpop2 = Cachex.invoke(cache, :lpop, "list")
    rpop1 = Cachex.invoke(cache, :rpop, "list")
    rpop2 = Cachex.invoke(cache, :rpop, "list")

    # verify that all results are as expected
    assert(lpop1 == {:ok, 1})
    assert(lpop2 == {:ok, 2})
    assert(rpop1 == {:ok, 4})
    assert(rpop2 == {:ok, 3})

    # verify the modified time was unchanged
    assert Cachex.inspect!(cache, {:entry, "list"}) ==
             entry(key: "list", modified: modified, value: [])

    # pop some extras to test avoiding writes
    lpop3 = Cachex.invoke(cache, :lpop, "list")
    rpop3 = Cachex.invoke(cache, :rpop, "list")

    # verify we stayed the same
    assert(lpop3 == {:ok, nil})
    assert(rpop3 == {:ok, nil})
  end

  # This test covers the ability to run commands tagged with the `:return type.
  # We simply test that we can return values as expected, as this is a very simple
  # implementation which doesn't have much room for error beyond user-created issues.
  test "invoking :read commands" do
    # create a test cache
    cache =
      TestUtils.create_cache(
        commands: [
          last: command(type: :read, execute: &List.last/1)
        ]
      )

    # define a validation function
    validate = fn list, expected ->
      # set a list inside the cache
      {:ok, true} = Cachex.put(cache, "list", list)

      # retrieve the last value
      last = Cachex.invoke(cache, :last, "list")

      # compare with the expected
      assert(last == {:ok, expected})
    end

    # ensure basic list works
    validate.([1, 2, 3, 4, 5], 5)
    validate.([1], 1)

    # ensure empty list works
    validate.([], nil)
  end

  # This test just makes sure that we correctly return an error in case the called
  # function is not a valid cache function. We make sure that missing functions
  # fail, as well as commands which have been badly formed due to arity or tag.
  test "invoking invalid commands" do
    # create a test cache
    cache = TestUtils.create_cache()

    # retrieve the state
    state = Services.Overseer.retrieve(cache)

    # modify the state to have fake commands
    state =
      cache(state,
        commands: %{
          fake_mod: {:modify, &{&1, &2}},
          fake_ret: {:return, &{&1, &2}}
        }
      )

    # try to invoke a missing command
    invoke1 = Cachex.invoke(state, :unknowns, "heh")

    # try to invoke bad arity commands
    invoke2 = Cachex.invoke(state, :fake_mod, "heh")
    invoke3 = Cachex.invoke(state, :fake_ret, "heh")

    # all should error
    assert(invoke1 == {:error, :invalid_command})
    assert(invoke2 == {:error, :invalid_command})
    assert(invoke3 == {:error, :invalid_command})
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "invoking commands in a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} =
      TestUtils.create_cache_cluster(2,
        commands: [
          last: command(type: :read, execute: &List.last/1)
        ]
      )

    # we know that 1 & 2 hash to different nodes
    {:ok, true} = Cachex.put(cache, 1, [1, 2, 3])
    {:ok, true} = Cachex.put(cache, 2, [4, 5, 6])

    # check the results from both keys in the nodes
    last1 = Cachex.invoke(cache, :last, 1)
    last2 = Cachex.invoke(cache, :last, 2)

    # check the command results
    assert(last1 == {:ok, 3})
    assert(last2 == {:ok, 6})
  end

  # A simple left pop for a List to remove the head and return the tail as the
  # modified list. This functions assumes the value is always a List.
  defp lpop([head | tail]),
    do: {head, tail}

  defp lpop([] = list),
    do: {nil, list}

  # A simple right pop for a List to remove the rightmost value and return the
  # rest as a modified list. This functions assumes the value is always a List.
  defp rpop([_head | _tail] = list),
    do: {List.last(list), :lists.droplast(list)}

  defp rpop([] = list),
    do: {nil, list}
end
