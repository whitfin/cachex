defmodule Cachex.Actions.PruneTest do
  use Cachex.Test.Case

  test "pruning a cache to a size" do
    # create a new test cache
    cache = TestUtils.create_cache()

    # insert 100 keys
    for i <- 1..100 do
      Cachex.put!(cache, i, i)
    end

    # guarantee we have 100 keys in the cache
    assert Cachex.size(cache) == 100

    # trigger a pruning down to 50 keys
    assert Cachex.prune(cache, 50) == {:ok, true}

    # verify that we're down to 50 keys
    assert Cachex.size(cache) == 45
  end

  test "pruning a cache to a size with a custom reclaim" do
    # create a new test cache
    cache = TestUtils.create_cache()

    # insert 100 keys
    for i <- 1..100 do
      Cachex.put!(cache, i, i)
    end

    # guarantee we have 100 keys in the cache
    assert Cachex.size(cache) == 100

    # trigger a pruning down to 50 keys, reclaiming 10%
    assert Cachex.prune(cache, 50, reclaim: 0) == {:ok, true}

    # verify that we're down to 50 keys
    assert Cachex.size(cache) == 50
  end

  # This test ensures that the cache eviction policy will evict any expired values
  # before removing the oldest. This is to make sure that we don't remove anything
  # without good reason. To verify this we add 50 keys with a TTL more recently
  # than those without and cross the cache limit. We then validate that all expired
  # keys have been purged, and no other keys have been removed as the purge takes
  # the cache size back under the maximum size.
  test "evicting by removing expired keys" do
    # create a new test cache
    cache = TestUtils.create_cache()

    # retrieve the cache state
    state = Services.Overseer.lookup(cache)

    # set 50 keys without ttl
    for x <- 1..50 do
      # set the key
      assert Cachex.put(state, x, x) == {:ok, true}

      # tick to make sure each has a new touch time
      :timer.sleep(1)
    end

    # set a more recent 50 keys
    for x <- 51..100 do
      # set the key
      assert Cachex.put(state, x, x, expire: 1) == {:ok, true}

      # tick to make sure each has a new touch time
      :timer.sleep(1)
    end

    # retrieve the cache size
    size1 = Cachex.size!(cache)

    # verify the cache size
    assert(size1 == 100)

    # add a new key to the cache to trigger oversize
    assert Cachex.put(state, 101, 101) == {:ok, true}

    # trigger the cache pruning down to 100 records
    assert Cachex.prune(cache, 100, reclaim: 0.3, buffer: -1) == {:ok, true}

    # verify the cache shrinks to 51%
    assert Cachex.size(state) == 51

    # our validation step
    validate = fn range, expected ->
      # iterate all keys in the range
      for x <- range do
        # retrieve whether the key exists and verify
        assert Cachex.exists?(state, x) == expected
      end
    end

    # verify the first 50 keys are retained
    validate.(1..50, true)

    # verify the second 50 are removed
    validate.(51..100, false)

    # verify the last key added is retained
    validate.(101..101, true)
  end
end
