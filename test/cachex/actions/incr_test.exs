defmodule Cachex.Actions.IncrTest do
  use Cachex.Test.Case

  # This test covers various combinations of incrementing cache items, by tweaking
  # the options provided alongside the calls. We validate the flags and values
  # coming back, as well as the fact they're forwarded to the hooks correctly.
  test "incrementing cache items" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = TestUtils.create_cache(hooks: [hook])

    # define write options
    opts1 = [default: 10]

    # increment some items, verify the values
    assert Cachex.incr(cache, "key1") == {:ok, 1}
    assert Cachex.incr(cache, "key1", 2) == {:ok, 3}
    assert Cachex.incr(cache, "key2", 1, opts1) == {:ok, 11}

    # verify the hooks were updated with the increment
    assert_receive({{:incr, ["key1", 1, []]}, {:ok, 1}})
    assert_receive({{:incr, ["key1", 2, []]}, {:ok, 3}})
    assert_receive({{:incr, ["key2", 1, ^opts1]}, {:ok, 11}})

    # retrieve all items, verify the items match
    assert Cachex.get(cache, "key1") == {:ok, 3}
    assert Cachex.get(cache, "key2") == {:ok, 11}
  end

  # This test covers the negative case where a value exists but is not an integer,
  # which naturally means we can't increment it properly. We just check for an
  # error flag in this case.
  test "incrementing a non-numeric value" do
    # create a test cache
    cache = TestUtils.create_cache()

    # set a non-numeric value
    assert Cachex.put(cache, "key", "value") == {:ok, true}

    # try to increment the value, we should receive an error
    assert Cachex.incr(cache, "key") == {:error, :non_numeric_value}
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "incrementing items in a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    assert Cachex.incr(cache, 1, 1) == {:ok, 1}
    assert Cachex.incr(cache, 2, 2) == {:ok, 2}

    # check the results of the calls across nodes
    assert Cachex.size(cache, local: true) == 1
    assert Cachex.size(cache, local: false) == 2
  end
end
