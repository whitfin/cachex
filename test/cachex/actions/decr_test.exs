defmodule Cachex.Actions.DecrTest do
  use Cachex.Test.Case

  # This test covers various combinations of decrementing cache items, by tweaking
  # the options provided alongside the calls. We validate the flags and values
  # coming back, as well as the fact they're forwarded to the hooks correctly.
  test "decrementing cache items" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = TestUtils.create_cache(hooks: [hook])

    # define write options
    opts1 = [default: 10]

    # decrement some items, verify the values
    assert Cachex.decr(cache, "key1") == -1
    assert Cachex.decr(cache, "key1", 2) == -3
    assert Cachex.decr(cache, "key2", 1, opts1) == 9

    # verify the hooks were updated with the decrement
    assert_receive {{:decr, ["key1", 1, []]}, -1}
    assert_receive {{:decr, ["key1", 2, []]}, -3}
    assert_receive {{:decr, ["key2", 1, ^opts1]}, 9}

    # retrieve all items, verify the items match
    assert Cachex.get(cache, "key1") == {:ok, -3}
    assert Cachex.get(cache, "key2") == {:ok, 9}
  end

  # This test covers the negative case where a value exists but is not an integer,
  # which naturally means we can't decrement it properly. We just check for an
  # error flag in this case.
  test "decrementing a non-numeric value" do
    # create a test cache
    cache = TestUtils.create_cache()

    # set a non-numeric value
    assert Cachex.put(cache, "key", "value") == {:ok, true}

    # try to increment the value, we should receive an error
    assert Cachex.decr(cache, "key", 1) == {:error, :non_numeric_value}
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "decrementing items in a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    assert Cachex.decr(cache, 1, 1) == -1
    assert Cachex.decr(cache, 2, 2) == -2

    # check the results of the calls across nodes
    assert Cachex.size(cache, local: true) == 1
    assert Cachex.size(cache, local: false) == 2
  end
end
