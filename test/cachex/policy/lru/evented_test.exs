defmodule Cachex.Policy.LRU.EventedTest do
  use Cachex.Test.Case

  test "evicting when a cache crosses a limit" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # define our cache limit
    limit =
      limit(
        size: 100,
        policy: Cachex.Policy.LRU,
        reclaim: 0.75,
        options: [batch_size: 25, immediate: true, silent: false]
      )

    # create a cache with a max size
    cache = TestUtils.create_cache(hooks: [hook], limit: limit)

    # retrieve the cache state
    state = Services.Overseer.retrieve(cache)

    # add 100 keys to the cache
    for x <- 1..100 do
      # add the entry to the cache
      {:ok, true} = Cachex.put(state, x, x)

      # tick to make sure each has a new touch time
      :timer.sleep(1)
    end

    # retrieve the cache size
    size1 = Cachex.size!(cache)

    # verify the cache size
    assert(size1 == 100)

    # flush all existing hook events
    TestUtils.flush()

    # run a no-op fetch to verify no change
    {:ignore, nil} =
      Cachex.fetch(state, 101, fn ->
        {:ignore, nil}
      end)

    # retrieve the cache size
    size2 = Cachex.size!(cache)

    # verify the cache size
    assert(size2 == 100)

    # store the current mod time
    previous = :os.system_time(1000)

    # tick to change ms
    :timer.sleep(1)

    # read the first key to re-touch
    {:ok, 1} = Cachex.get(state, 1)

    # wait for the touch async
    TestUtils.poll(250, true, fn ->
      modified =
        state
        |> Cachex.inspect!({:entry, 1})
        |> entry(:modified)

      assert modified > previous
    end)

    # add a new key to the cache to trigger evictions
    {:ok, true} = Cachex.put(state, 101, 101)

    # verify the cache shrinks to 25%
    TestUtils.poll(250, 25, fn ->
      Cachex.size!(state)
    end)

    # our validation step
    validate = fn range, expected ->
      # iterate all keys in the range
      for x <- range do
        # retrieve whether the key exists
        exists = Cachex."exists?!"(state, x)

        # verify whether it exists
        assert(exists == expected)
      end
    end

    # verify the 1st key was refreshed
    validate.(1..1, true)

    # verify the next 76 keys are removed
    validate.(2..77, false)

    # verify the last 24 are retained
    validate.(78..101, true)

    # finally, verify hooks are notified
    assert_receive({{:clear, [[]]}, {:ok, 76}})

    # retrieve the policy hook definition
    cache(hooks: hooks(post: [hook1 | _])) = state

    # just ensure that notifying errors to the policy doesn't cause a crash
    Services.Informant.notify([hook1], {:action, []}, {:error, false})
  end
end
