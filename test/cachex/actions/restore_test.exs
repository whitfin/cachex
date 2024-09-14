defmodule Cachex.Actions.RestoreTest do
  use Cachex.Test.Case

  # This test covers the backing up of a cache to a local disk location. We set
  # a value, save to disk, then clear the cache. We then load the backup file to
  # verify that the values come back. We also verify that bad reads correctly pass
  # their errors straight back through to the calling function.
  test "restoring a cache backup from a local disk" do
    # locate the temporary directory
    tmp = System.tmp_dir!()

    # create a test cache
    cache = TestUtils.create_cache()
    start = now()

    # add some cache entries
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, true} = Cachex.put(cache, 2, 2, expire: 1)
    {:ok, true} = Cachex.put(cache, 3, 3, expire: 10_000)

    # create a local path to write to
    path = Path.join(tmp, TestUtils.gen_rand_bytes(8))

    # save the cache to a local file
    result1 = Cachex.save(cache, path)
    result2 = Cachex.clear(cache)
    result3 = Cachex.size(cache)

    # verify the result and clearance
    assert(result1 == {:ok, true})
    assert(result2 == {:ok, 3})
    assert(result3 == {:ok, 0})

    # wait a while before re-load
    :timer.sleep(50)

    # load the cache from the disk
    result4 = Cachex.restore(cache, path)
    result5 = Cachex.size(cache)
    result6 = Cachex.ttl!(cache, 3)

    # verify that the load was ok
    assert(result4 == {:ok, 2})
    assert(result5 == {:ok, 2})

    # verify TTL offsetting happens
    assert_in_delta(result6, 10_000 - (now() - start), 5)

    # reload a bad file from disk (should not be trusted)
    result7 = Cachex.restore(cache, tmp, trust: false)

    # verify the result failed
    assert(result7 == {:error, :unreachable_file})
  end
end
