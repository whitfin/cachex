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
    assert Cachex.put(cache, "key1", 1)
    assert Cachex.put(cache, "key2", 2, expire: 1)

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
    assert Cachex.fetch(cache, "key1", fb_opt1) == 1
    assert Cachex.fetch(cache, "key2", fb_opt1) == {:commit, "2yek"}

    # fetch keys with a provided fallback
    assert Cachex.fetch(cache, "key3", fb_opt1) == {:commit, "3yek"}
    assert Cachex.fetch(cache, "key4", fb_opt2) == {:commit, "4yek"}
    assert Cachex.fetch(cache, "key5", fb_opt3) == {:ignore, "5yek"}
    assert Cachex.fetch(cache, "key6", fb_opt4) == {:commit, "6yek"}

    # assert we receive valid notifications
    assert_receive {{:fetch, ["key1", ^fb_opt1, []]}, 1}
    assert_receive {{:fetch, ["key2", ^fb_opt1, []]}, {:commit, "2yek"}}
    assert_receive {{:fetch, ["key3", ^fb_opt1, []]}, {:commit, "3yek"}}
    assert_receive {{:fetch, ["key4", ^fb_opt2, []]}, {:commit, "4yek"}}
    assert_receive {{:fetch, ["key5", ^fb_opt3, []]}, {:ignore, "5yek"}}
    assert_receive {{:fetch, ["key6", ^fb_opt4, []]}, {:commit, "6yek"}}

    # check we received valid purge actions for the TTL
    assert_receive {{:purge, [[]]}, 1}

    # retrieve the loaded keys
    assert Cachex.get(cache, "key3") == "3yek"
    assert Cachex.get(cache, "key4") == "4yek"
    assert Cachex.get(cache, "key5") == nil
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
      assert Cachex.get(cache, "key1_count") == 1
    end
  end

  test "fetching and setting an expiration on a key from a fallback" do
    # create a test cache
    cache = TestUtils.create_cache()

    # create a fallback with an expiration
    purged = [expire: 60000]
    fb_opt = &{:commit, String.reverse(&1), purged}

    # fetch our key using our fallback
    assert Cachex.fetch(cache, "key", fb_opt) == {:commit, "yek"}

    # check we have a set expiration
    assert_in_delta Cachex.ttl(cache, "key"), 60000, 250
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
    assert Cachex.fetch(cache, 1, &Integer.to_string/1) == {:commit, "1"}
    assert Cachex.fetch(cache, 2, &Integer.to_string/1) == {:commit, "2"}

    # try to retrieve both of the set keys
    assert Cachex.get(cache, 1) == "1"
    assert Cachex.get(cache, 2) == "2"
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

  # This test covers whether $callers is correctly propagated through to the
  # fallback function to allow things like mocking, etc.
  test "fetching functions have access to $callers" do
    # create a test cache
    cache = TestUtils.create_cache()
    cache = Services.Overseer.lookup(cache)

    # process chain
    parent = self()
    courier = Services.locate(cache, Services.Courier)

    # trigger a fetch in another process
    Cachex.fetch(cache, "key", fn ->
      send(parent, Process.get(:"$callers"))
      {:ignore, nil}
    end)

    # check callers are the Courier and us
    assert_receive [^courier, ^parent]
  end
end
