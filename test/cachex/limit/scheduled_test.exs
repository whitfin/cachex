defmodule Cachex.Limit.ScheduledTest do
  use Cachex.Test.Case

  # This test just ensures that there are no artificial limits placed on a cache
  # by adding 5000 keys and making sure they're not evicted. It simply serves as
  # validation that there are no bad defaults set anywhere.
  test "evicting with no upper bound" do
    # create a cache with no max size
    cache = TestUtils.create_cache()

    # retrieve the cache state
    state = Services.Overseer.lookup(cache)

    # add 5000 keys to the cache
    for x <- 1..5000 do
      {:ok, true} = Cachex.put(state, x, x)
    end

    # retrieve the cache size
    count = Cachex.size!(state)

    # make sure all keys are there
    assert(count == 5000)
  end

  # This test ensures that a cache will cap caches at a given limit by trimming
  # caches by a given size once they cross a given threshold. We ensure that the
  # size is trimmed properly and the oldest entries are evicted first, with the
  # newest entries kept in the cache. Finally we make sure that all hooks are
  # notified of the evictions that occurred.
  test "evicting when a cache crosses a limit" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a cache with a max size
    cache =
      TestUtils.create_cache(
        hooks: [
          hook,
          hook(
            module: Cachex.Limit.Scheduled,
            args: {
              100,
              [
                buffer: 25,
                reclaim: 0.75
              ],
              [
                frequency: 100
              ]
            }
          )
        ]
      )

    # retrieve the cache state
    state = Services.Overseer.lookup(cache)

    # add 1000 keys to the cache
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

    # verify the first 76 keys are removed
    validate.(1..76, false)

    # verify the latest 25 are retained
    validate.(77..101, true)

    # finally, verify hooks are notified
    assert_receive({{:clear, [[]]}, {:ok, 76}})

    # retrieve the policy hook definition
    cache(hooks: hooks(post: [hook1 | _])) = state

    # just ensure that notifying errors to the policy doesn't cause a crash
    Services.Informant.notify([hook1], {:action, []}, {:error, false})
  end
end
