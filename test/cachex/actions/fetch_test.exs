defmodule Cachex.Actions.FetchTest do
  use Cachex.Test.Case

  # This test verifies that we can retrieve keys from the cache with the
  # ability to compute values if they're missing. If a key has expired,
  # the value is not returned and the hooks are updated with an eviction.
  # If the provided function is arity 1, we ignore the state argument.
  test "fetching keys from a cache" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = TestUtils.create_cache(hooks: [hook])

    # set some keys in the cache
    {:ok, true} = Cachex.put(cache, "key1", 1)
    {:ok, true} = Cachex.put(cache, "key2", 2, expire: 1)

    # wait for the TTL to pass
    :timer.sleep(2)

    # flush all existing messages
    TestUtils.flush()

    # define the fallback options
    fb_opt1 = &String.reverse/1
    fb_opt2 = &{:commit, String.reverse(&1)}
    fb_opt3 = &{:ignore, String.reverse(&1)}
    fb_opt4 = fn -> "6yek" end

    # fetch the first and second keys
    result1 = Cachex.fetch(cache, "key1", fb_opt1)
    result2 = Cachex.fetch(cache, "key2", fb_opt1)

    # verify fetching an existing key
    assert(result1 == {:ok, 1})

    # verify the ttl expiration
    assert(result2 == {:commit, "2yek"})

    # fetch keys with a provided fallback
    result3 = Cachex.fetch(cache, "key3", fb_opt1)
    result4 = Cachex.fetch(cache, "key4", fb_opt2)
    result5 = Cachex.fetch(cache, "key5", fb_opt3)
    result6 = Cachex.fetch(cache, "key6", fb_opt4)

    # verify the fallback fetches
    assert(result3 == {:commit, "3yek"})
    assert(result4 == {:commit, "4yek"})
    assert(result5 == {:ignore, "5yek"})
    assert(result6 == {:commit, "6yek"})

    # assert we receive valid notifications
    assert_receive({{:fetch, ["key1", ^fb_opt1, []]}, ^result1})
    assert_receive({{:fetch, ["key2", ^fb_opt1, []]}, ^result2})
    assert_receive({{:fetch, ["key3", ^fb_opt1, []]}, ^result3})
    assert_receive({{:fetch, ["key4", ^fb_opt2, []]}, ^result4})
    assert_receive({{:fetch, ["key5", ^fb_opt3, []]}, ^result5})
    assert_receive({{:fetch, ["key6", ^fb_opt4, []]}, ^result6})

    # check we received valid purge actions for the TTL
    assert_receive({{:purge, [[]]}, {:ok, 1}})

    # retrieve the loaded keys
    value1 = Cachex.get(cache, "key3")
    value2 = Cachex.get(cache, "key4")
    value3 = Cachex.get(cache, "key5")

    # committed keys should now exist
    assert(value1 == {:ok, "3yek"})
    assert(value2 == {:ok, "4yek"})

    # ignored keys should not exist
    assert(value3 == {:ok, nil})
  end

  # This test ensures that the fallback is executed just once when a
  # fallback commit and another fetch on the same key occur simultaneously.
  test "fetching and committing the same key simultaneously from a fallback" do
    for _ <- 1..10 do
      # create a test cache
      cache = TestUtils.create_cache()

      # basic fallback
      fallback1 = fn ->
        Cachex.incr!(cache, "key1_count")
        {:commit, "val"}
      end

      # secondary fallback
      fallback2 = fn ->
        # incr! exists to match the fallback1 exec time
        Cachex.incr!(cache, "key2_count")
        Cachex.fetch(cache, "key1", fallback1)
      end

      # task generator for key/fallback
      fetch = fn key, fallback ->
        Task.async(fn ->
          Cachex.fetch(cache, key, fallback)
        end)
      end

      # spawn two async tasks to cause a race
      task1 = fetch.("key1", fallback1)
      task2 = fetch.("key2", fallback2)

      # wait for both
      Task.await(task1)
      Task.await(task2)

      # check the fallback was only executed a single time
      assert Cachex.get(cache, "key1_count") == {:ok, 1}
    end
  end

  test "fetching and setting an expiration on a key from a fallback" do
    # create a test cache
    cache = TestUtils.create_cache()

    # create a fallback with an expiration
    purged = [expire: 60000]
    fb_opt = &{:commit, String.reverse(&1), purged}

    # fetch our key using our fallback
    result = Cachex.fetch(cache, "key", fb_opt)

    # verify fetching an existing key
    assert(result == {:commit, "yek"})

    # fetch back the expiration of the key
    expiration = Cachex.ttl!(cache, "key")

    # check we have a set expiration
    assert_in_delta(expiration, 60000, 250)
  end

  # This test verifies that this action is correctly distributed across
  # a cache cluster, instead of just the local node. We're not concerned
  # about the actual behaviour here, only the routing of the action.
  @tag distributed: true
  test "fetching keys from a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes - have to make sure that we
    # use a known function, otherwise it fails with an undefined function.
    {:commit, "1"} = Cachex.fetch(cache, 1, &Integer.to_string/1)
    {:commit, "2"} = Cachex.fetch(cache, 2, &Integer.to_string/1)

    # try to retrieve both of the set keys
    get1 = Cachex.get(cache, 1)
    get2 = Cachex.get(cache, 2)

    # both should come back
    assert(get1 == {:ok, "1"})
    assert(get2 == {:ok, "2"})
  end

  # This test ensures that the fallback is executed just once per key, per TTL,
  # due to a race condition that previously existed inside the Courier. If the
  # bug were to reappear, this test should fail and catch it.
  test "fetching will only call fallback once per key" do
    # create a test cache
    cache = TestUtils.create_cache()

    # create a test agent to hold our test state
    {:ok, agent} = Agent.start_link(fn -> %{} end)

    # execute 1000 fetches
    for idx <- 1..1000 do
      # with a unique key
      key = "key_#{idx}"
      count = System.schedulers_online() * 2

      # track all changes caused by fetch
      tasks =
        Task.async_stream(1..count, fn _ ->
          Cachex.fetch(cache, key, fn ->
            Agent.update(agent, fn state ->
              Map.update(state, key, 1, &(&1 + 1))
            end)
          end)
        end)

      # run the tasks together
      Stream.run(tasks)
    end

    # fetch the agent state
    state = Agent.get(agent, & &1)

    # determine call frequency
    calls =
      Enum.reduce(state, %{}, fn {_key, count}, acc ->
        case acc do
          %{^count => value} -> %{acc | count => value + 1}
          %{} -> Map.put(acc, count, 1)
        end
      end)

    # all should have been called just once
    assert %{1 => 1000} == calls
  end

  test "fallback function has test process in $callers" do
    test_process = self()
    callers_reference = make_ref()

    cache = TestUtils.create_cache()

    fallback_fun = fn ->
      send(test_process, {callers_reference, Process.get(:"$callers")})
      "value"
    end

    {:commit, "value"} = Cachex.fetch(cache, "key", fallback_fun)

    assert_receive({^callers_reference, callers})
    assert test_process in callers
  end
end
