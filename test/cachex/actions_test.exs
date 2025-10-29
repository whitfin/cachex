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
    state = Services.Overseer.lookup(cache)

    # write several values
    assert Cachex.put(cache, 1, 1) == {:ok, true}
    assert Cachex.put(cache, 2, 2, expire: 1) == {:ok, true}

    # let the TTL expire
    :timer.sleep(2)

    # read back the values from the table
    record = Cachex.Actions.read(state, 1)
    assert match?(entry(key: 1, value: 1), record)

    # read back missing values from the table
    assert Cachex.Actions.read(state, 2) == nil
    assert Cachex.Actions.read(state, 3) == nil

    # we should receive the purge of the second key
    assert_receive {{:purge, [[]]}, 1}

    # verify if the second key exists
    refute Cachex.exists?(cache, 2)
  end

  test "carrying out generic write actions" do
    # create a test cache
    cache = TestUtils.create_cache()

    # retrieve the state
    state = Services.Overseer.lookup(cache)

    # write some values into the cache
    write1 =
      Cachex.Actions.write(
        state,
        entry(
          key: "key",
          value: "value",
          modified: 1
        )
      )

    # verify the write
    assert write1 == {:ok, true}

    # validate the value
    assert Cachex.Actions.read(state, "key") ==
             entry(
               key: "key",
               value: "value",
               modified: 1
             )

    # attempt to update some values
    assert Cachex.Actions.update(state, "key", entry_mod(value: "yek"))
    refute Cachex.Actions.update(state, "nop", entry_mod(value: "yek"))

    # validate the update took effect
    assert Cachex.Actions.read(state, "key") ==
             entry(
               key: "key",
               value: "yek",
               modified: 1
             )
  end

  # This test just ensures that we correctly convert return values to either a
  # :commit Tuple or an :ignore Tuple. We also make sure to verify that the default
  # behaviour is a :commit Tuple for backwards compatibility.
  test "formatting commit/ignore return values" do
    # format all values are acceptable as is if they're matching the pattern
    assert Cachex.Actions.format_fetch_value({:commit, true}) == {:commit, true}
    assert Cachex.Actions.format_fetch_value({:ignore, true}) == {:ignore, true}
    assert Cachex.Actions.format_fetch_value({:error, true}) == {:error, true}
    assert Cachex.Actions.format_fetch_value({:commit, true, []}) == {:commit, true, []}

    # the value should be converted to the first
    assert Cachex.Actions.format_fetch_value(true) == {:commit, true}
  end

  # Simple test to ensure that commit normalization correctly assigns
  # options to a commit tuple without, and maintains those with.
  test "normalizing formatted :commit values" do
    assert Cachex.Actions.normalize_commit({:commit, true}) == {:commit, true, []}
    assert Cachex.Actions.normalize_commit({:commit, true, []}) == {:commit, true, []}
  end

  # This test just provides basic coverage of the write_op function, by using
  # a prior value to determine the correct Action to use to write a value.
  test "retrieving a module name to write with" do
    assert Cachex.Actions.write_op(nil) == :put
    assert Cachex.Actions.write_op("value") == :update
  end
end
