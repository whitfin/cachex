defmodule Cachex.Actions.WarmTest do
  use Cachex.Test.Case

  # This test covers the basic case of manually rewarming a cache,
  # after manually clearing it but checking again before the schedule.
  test "manually warming a cache" do
    # create a test warmer to pass to the cache
    TestUtils.create_warmer(:manual_warmer1, fn _ ->
      {:ok, [{1, 1}]}
    end)

    # create a cache instance with a warmer
    cache =
      TestUtils.create_cache(
        warmers: [
          warmer(
            module: :manual_warmer1,
            name: :manual_warmer1
          )
        ]
      )

    # check that the key was warmed
    assert Cachex.get(cache, 1) == 1

    # clean out our cache entries
    assert Cachex.clear(cache) == 1
    assert Cachex.get(cache, 1) == nil

    # manually trigger a cache warming of all modules
    assert Cachex.warm(cache) == [:manual_warmer1]

    # wait for the warming
    :timer.sleep(50)

    # check that our key has been put back
    assert Cachex.get!(cache, 1) == 1
  end

  test "manually warming a cache and awaiting results" do
    # create a test warmer to pass to the cache
    TestUtils.create_warmer(:manual_warmer2, fn _ ->
      {:ok, [{1, 1}]}
    end)

    # create a cache instance with a warmer
    cache =
      TestUtils.create_cache(
        warmers: [
          warmer(
            module: :manual_warmer2,
            name: :manual_warmer2
          )
        ]
      )

    # check that the key was warmed
    assert Cachex.get(cache, 1) == 1

    # clean out our cache entries
    assert Cachex.clear(cache) == 1
    assert Cachex.get(cache, 1) == nil

    # manually trigger a cache warming of all modules
    assert Cachex.warm(cache, wait: true) == [:manual_warmer2]
    assert Cachex.get(cache, 1) == 1
  end

  # This test covers the case where you manually specify a list of modules
  # to use for the warming. It also covers cases where no modules match the
  # provided list, and therefore no cache warming actually executes.
  test "manually warming a cache using specific warmers" do
    # create a test warmer to pass to the cache
    TestUtils.create_warmer(:manual_warmer3, fn _ ->
      {:ok, [{1, 1}]}
    end)

    # create a cache instance with a warmer
    cache =
      TestUtils.create_cache(
        warmers: [
          warmer(
            module: :manual_warmer3,
            name: :manual_warmer3
          )
        ]
      )

    # check that the key was warmed
    assert Cachex.get(cache, 1) == 1

    # clean out our cache entries
    assert Cachex.clear(cache) == 1
    assert Cachex.get(cache, 1) == nil

    # manually trigger a cache warming
    assert Cachex.warm(cache, only: []) == []

    # wait for the warming
    :timer.sleep(50)

    # check that our key was never put back
    assert Cachex.get(cache, 1) == nil

    # manually trigger a cache warming, specifying our module
    assert Cachex.warm(cache, only: [:manual_warmer3]) == [:manual_warmer3]

    # wait for the warming
    :timer.sleep(50)

    # check that our key has been put back
    assert Cachex.get(cache, 1) == 1
  end
end
