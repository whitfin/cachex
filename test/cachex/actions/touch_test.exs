defmodule Cachex.Actions.TouchTest do
  use Cachex.Test.Case

  # This test ensures that we can safely update the touch time of a key without
  # affecting when the key will be removed. We verify the TTL before and after
  # to make sure that there is no impact to the TTL, but also ensure that the
  # touch time on the record has been modified.
  test "touching a key in the cache" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = TestUtils.create_cache(hooks: [hook])

    # pull back the state
    state = Services.Overseer.lookup(cache)

    # add some keys to the cache
    assert Cachex.put(cache, 1, 1)
    assert Cachex.put(cache, 2, 2, expire: 1000)

    # clear messages
    TestUtils.flush()

    # retrieve the raw records
    entry(modified: modified1, expiration: expiration1) =
      Cachex.Actions.read(state, 1)

    entry(modified: modified2, expiration: expiration2) =
      Cachex.Actions.read(state, 2)

    # the first TTL should be nil
    assert expiration1 == nil

    # the second TTL should be roughly 1000
    assert_in_delta expiration2, 995, 6

    # wait for 50ms
    :timer.sleep(50)

    # touch the keys
    assert Cachex.touch(cache, 1)
    assert Cachex.touch(cache, 2)
    refute Cachex.touch(cache, 3)

    # verify the hooks were updated with the message
    assert_receive {{:touch, [1, []]}, true}
    assert_receive {{:touch, [2, []]}, true}
    assert_receive {{:touch, [3, []]}, false}

    # retrieve the raw records again
    entry(modified: modified3, expiration: expiration3) =
      Cachex.Actions.read(state, 1)

    entry(modified: modified4, expiration: expiration4) =
      Cachex.Actions.read(state, 2)

    # the first expiration should still be nil
    assert expiration3 == nil

    # the first touch time should be roughly 50ms after the first one
    assert_in_delta modified3, modified1 + 60, 11

    # the second expiration should be roughly 50ms lower than the first
    assert_in_delta expiration4, expiration2 - 60, 11

    # the second touch time should also be 50ms after the first one
    assert_in_delta modified4, modified2 + 60, 11

    # it should be roughly 945ms left
    assert_in_delta Cachex.ttl(cache, 2), 940, 11
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "adding new entries to a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    assert Cachex.put(cache, 1, 1)
    assert Cachex.put(cache, 2, 2)

    # wait a little
    :timer.sleep(10)

    # sort to guarantee we're checking well
    [record1, record2] =
      cache |> Cachex.export() |> Enum.sort()

    # unpack the records touch time
    entry(modified: modified1) = record1
    entry(modified: modified2) = record2

    # now touch both keys
    assert Cachex.touch(cache, 1)
    assert Cachex.touch(cache, 2)

    # sort to guarantee we're checking well
    [record3, record4] =
      cache |> Cachex.export() |> Enum.sort()

    # unpack the records touch time
    entry(modified: modified3) = record3
    entry(modified: modified4) = record4

    # new modified should be larger than old
    assert modified3 > modified1
    assert modified4 > modified2
  end
end
