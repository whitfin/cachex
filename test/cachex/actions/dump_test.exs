defmodule Cachex.Actions.DumpTest do
  use CachexCase

  # This test covers the backing up of a cache to a local disk location. We only
  # cover the happy path as there are separate tests covering issues with the
  # path provided to the dump. We set a value, dump to disk, then clear the cache.
  # We then load the backup file to verify that the values come back.
  test "backing up a cache to a local disk" do
    # locate the temporary directory
    tmp = System.tmp_dir!()

    # create a test cache
    cache = Helper.create_cache()

    # add some cache entries
    { :ok, true } = Cachex.put(cache, 1, 1)

    # create a local path to write to
    path = Path.join(tmp, Helper.gen_rand_bytes(8))

    # dump the cache to a local file
    result1 = Cachex.dump(cache, path)
    result2 = Cachex.clear(cache)
    result3 = Cachex.size(cache)

    # verify the result and clearance
    assert(result1 == { :ok, true })
    assert(result2 == { :ok, 1 })
    assert(result3 == { :ok, 0 })

    # load the cache from the disk
    result4 = Cachex.load(cache, path)
    result5 = Cachex.size(cache)

    # verify that the load was ok
    assert(result4 == { :ok, true })
    assert(result5 == { :ok, 1 })
  end

end
