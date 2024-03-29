defmodule Cachex.Actions.LoadTest do
  use CachexCase

  # This test covers the backing up of a cache to a local disk location. We set
  # a value, dump to disk, then clear the cache. We then load the backup file to
  # verify that the values come back. We also verify that bad reads correctly pass
  # their errors straight back through to the calling function.
  test "loading a cache backup from a local disk" do
    # locate the temporary directory
    tmp = System.tmp_dir!()

    # create a test cache
    cache = Helper.create_cache()
    start = now()

    # add some cache entries
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, true} = Cachex.put(cache, 2, 2, ttl: 1)
    {:ok, true} = Cachex.put(cache, 3, 3, ttl: 10_000)

    # create a local path to write to
    path = Path.join(tmp, Helper.gen_rand_bytes(8))

    # dump the cache to a local file
    result1 = Cachex.dump(cache, path)
    result2 = Cachex.clear(cache)
    result3 = Cachex.size(cache)

    # verify the result and clearance
    assert(result1 == {:ok, true})
    assert(result2 == {:ok, 3})
    assert(result3 == {:ok, 0})

    # wait a while before re-load
    :timer.sleep(50)

    # load the cache from the disk
    result4 = Cachex.load(cache, path)
    result5 = Cachex.size(cache)
    result6 = Cachex.ttl!(cache, 3)

    # verify that the load was ok
    assert(result4 == {:ok, true})
    assert(result5 == {:ok, 2})

    # verify TTL offsetting happens
    assert_in_delta(result6, 10_000 - (now() - start), 5)

    # reload a bad file from disk (should not be trusted)
    result7 = Cachex.load(cache, tmp, trusted: false)

    # verify the result failed
    assert(result7 == {:error, :unreachable_file})
  end
end
