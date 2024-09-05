defmodule Cachex.ActionsTest do
  use Cachex.Test.Case

  require Cachex.Actions

  # Bind any required hooks for test execution
  setup_all do
    ForwardHook.bind(
      actions_forward_hook_pre: [type: :pre],
      actions_forward_hook_post: [type: :post]
    )

    :ok
  end

  test "carrying out generic read actions" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = TestUtils.create_cache(hooks: [hook])

    # retrieve the state
    state = Services.Overseer.retrieve(cache)

    # write several values
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, true} = Cachex.put(cache, 2, 2, ttl: 1)

    # let the TTL expire
    :timer.sleep(2)

    # read back the values from the table
    record1 = Cachex.Actions.read(state, 1)
    record2 = Cachex.Actions.read(state, 2)
    record3 = Cachex.Actions.read(state, 3)

    # the first should find a record
    assert(match?(entry(key: 1, ttl: nil, value: 1), record1))

    # the second should expire
    assert(record2 == nil)

    # the third is missing
    assert(record3 == nil)

    # we should receive the purge of the second key
    assert_receive({{:purge, [[]]}, {:ok, 1}})

    # verify if the second key exists
    exists1 = Cachex.exists?(cache, 2)

    # it shouldn't exist
    assert(exists1 == {:ok, false})
  end

  test "carrying out generic write actions" do
    # create a test cache
    cache = TestUtils.create_cache()

    # retrieve the state
    state = Services.Overseer.retrieve(cache)

    # write some values into the cache
    write1 =
      Cachex.Actions.write(
        state,
        entry(
          key: "key",
          modified: 1,
          value: "value"
        )
      )

    # verify the write
    assert(write1 == {:ok, true})

    # retrieve the value
    value1 = Cachex.Actions.read(state, "key")

    # validate the value
    assert(
      value1 ==
        entry(
          key: "key",
          modified: 1,
          value: "value"
        )
    )

    # attempt to update some values
    update1 = Cachex.Actions.update(state, "key", entry_mod(value: "yek"))
    update2 = Cachex.Actions.update(state, "nop", entry_mod(value: "yek"))

    # the first should be ok
    assert(update1 == {:ok, true})

    # the second is missing
    assert(update2 == {:ok, false})

    # retrieve the value
    value2 = Cachex.Actions.read(state, "key")

    # validate the update took effect
    assert(
      value2 ==
        entry(
          key: "key",
          modified: 1,
          value: "yek"
        )
    )
  end

  # This test just ensures that we correctly convert return values to either a
  # :commit Tuple or an :ignore Tuple. We also make sure to verify that the default
  # behaviour is a :commit Tuple for backwards compatibility.
  test "formatting commit/ignore return values" do
    # define our base Tuples to test against
    tuple1 = {:commit, true}
    tuple2 = {:ignore, true}
    tuple3 = {:error, true}
    tuple4 = {:commit, true, []}

    # define our base value
    value1 = true

    # format all values
    result1 = Cachex.Actions.format_fetch_value(tuple1)
    result2 = Cachex.Actions.format_fetch_value(tuple2)
    result3 = Cachex.Actions.format_fetch_value(tuple3)
    result4 = Cachex.Actions.format_fetch_value(tuple4)
    result5 = Cachex.Actions.format_fetch_value(value1)

    # the first three should persist
    assert(result1 == tuple1)
    assert(result2 == tuple2)
    assert(result3 == tuple3)
    assert(result4 == tuple4)

    # the value should be converted to the first
    assert(result5 == tuple1)
  end

  # Simple test to ensure that commit normalization correctly assigns
  # options to a commit tuple without, and maintains those with.
  test "normalizing formatted :commit values" do
    # define our base Tuples to test against
    tuple1 = {:commit, true}
    tuple2 = {:commit, true, []}

    # normalize all values
    result1 = Cachex.Actions.normalize_commit(tuple1)
    result2 = Cachex.Actions.normalize_commit(tuple2)

    # both should have options
    assert(result1 == tuple2)
    assert(result2 == tuple2)
  end

  # This test just provides basic coverage of the write_op function, by using
  # a prior value to determine the correct Action to use to write a value.
  test "retrieving a module name to write with" do
    # ask for some modules
    result1 = Cachex.Actions.write_op(nil)
    result2 = Cachex.Actions.write_op("value")

    # the first should be Set actions
    assert(result1 == :put)

    # the second should be an Update
    assert(result2 == :update)
  end
end
