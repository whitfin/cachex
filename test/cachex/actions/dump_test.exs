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

  # This test covers the backing up of a cache cluster to a local disk location. We
  # basically copy the local example, except that we run it against a cluster with
  # several nodes - the entire cluster should be backed up to the local disk.
  @tag distributed: true
  test "backing up a cache cluster to a local disk" do
    # locate the temporary directory
    tmp = System.tmp_dir!()

    # create a new cache cluster for cleaning
    { cache, _nodes } = Helper.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    { :ok, true } = Cachex.put(cache, 1, 1)
    { :ok, true } = Cachex.put(cache, 2, 2)

    # create a local path to write to
    path1 = Path.join(tmp, Helper.gen_rand_bytes(8))
    path2 = Path.join(tmp, Helper.gen_rand_bytes(8))

    # dump the cache to a local file for local/remote
    dump1 = Cachex.dump(cache, path1, [ local: true ])
    dump2 = Cachex.dump(cache, path2, [ local: false ])

    # verify the dump results
    assert(dump1 == { :ok, true })
    assert(dump2 == { :ok, true })

    # clear the cache to remove all
    { :ok, 2 } = Cachex.clear(cache)

    # load the local cache from the disk
    load1 = Cachex.load(cache, path1)
    size1 = Cachex.size(cache)

    # verify that the load was ok
    assert(load1 == { :ok, true })
    assert(size1 == { :ok, 1 })

    # clear the cache again
    { :ok, 1 } = Cachex.clear(cache)

    # load the full cache from the disk
    load2 = Cachex.load(cache, path2)
    size2 = Cachex.size(cache)

    # verify that the load was ok
    assert(load2 == { :ok, true })
    assert(size2 == { :ok, 2 })
  end
end
