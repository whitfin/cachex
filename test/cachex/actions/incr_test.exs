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

    # increment some items
    incr1 = Cachex.incr(cache, "key1")
    incr2 = Cachex.incr(cache, "key1", 2)
    incr3 = Cachex.incr(cache, "key2", 1, opts1)

    # the first result should be 1
    assert(incr1 == {:ok, 1})

    # the second result should be 3
    assert(incr2 == {:ok, 3})

    # the third result should be 11
    assert(incr3 == {:ok, 11})

    # verify the hooks were updated with the increment
    assert_receive({{:incr, ["key1", 1, []]}, ^incr1})
    assert_receive({{:incr, ["key1", 2, []]}, ^incr2})
    assert_receive({{:incr, ["key2", 1, ^opts1]}, ^incr3})

    # retrieve all items
    value1 = Cachex.get(cache, "key1")
    value2 = Cachex.get(cache, "key2")

    # verify the items match
    assert(value1 == {:ok, 3})
    assert(value2 == {:ok, 11})
  end

  # This test covers the negative case where a value exists but is not an integer,
  # which naturally means we can't increment it properly. We just check for an
  # error flag in this case.
  test "incrementing a non-numeric value" do
    # create a test cache
    cache = TestUtils.create_cache()

    # set a non-numeric value
    {:ok, true} = Cachex.put(cache, "key", "value")

    # try to increment the value
    result = Cachex.incr(cache, "key")

    # we should receive an error
    assert(result == {:error, :non_numeric_value})
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "incrementing items in a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    {:ok, 1} = Cachex.incr(cache, 1, 1)
    {:ok, 2} = Cachex.incr(cache, 2, 2)

    # check the results of the calls across nodes
    size1 = Cachex.size(cache, local: true)
    size2 = Cachex.size(cache, local: false)

    # one local, two total
    assert(size1 == {:ok, 1})
    assert(size2 == {:ok, 2})
  end
end
