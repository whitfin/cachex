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
    assert Cachex.put(cache, "list", [1, 2, 3, 4]) == :ok

    # retrieve the raw record
    entry(key: "list", modified: modified) =
      Cachex.inspect(cache, {:entry, "list"})

    # verify that all results are as expected
    assert Cachex.invoke(cache, :lpop, "list") == 1
    assert Cachex.invoke(cache, :lpop, "list") == 2
    assert Cachex.invoke(cache, :rpop, "list") == 4
    assert Cachex.invoke(cache, :rpop, "list") == 3

    # verify the modified time was unchanged
    assert Cachex.inspect(cache, {:entry, "list"}) ==
             entry(key: "list", modified: modified, value: [])

    # pop some extras to test avoiding writes
    assert Cachex.invoke(cache, :lpop, "list") == nil
    assert Cachex.invoke(cache, :rpop, "list") == nil
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
      assert Cachex.put(cache, "list", list) == :ok

      # retrieve the last value, compare with the expected
      assert Cachex.invoke(cache, :last, "list") == expected
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
    state = Services.Overseer.lookup(cache)

    # modify the state to have fake commands
    state =
      cache(state,
        commands: %{
          fake_mod: {:modify, &{&1, &2}},
          fake_ret: {:return, &{&1, &2}}
        }
      )

    # try to invoke a missing command
    assert Cachex.invoke(state, :unknowns, "heh") == {:error, :invalid_command}

    # try to invoke bad arity commands
    assert Cachex.invoke(state, :fake_mod, "heh") == {:error, :invalid_command}
    assert Cachex.invoke(state, :fake_ret, "heh") == {:error, :invalid_command}
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
    assert Cachex.put(cache, 1, [1, 2, 3]) == :ok
    assert Cachex.put(cache, 2, [4, 5, 6]) == :ok

    # check the results from both keys in the nodes
    assert Cachex.invoke(cache, :last, 1) == 3
    assert Cachex.invoke(cache, :last, 2) == 6
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
