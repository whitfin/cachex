defmodule Cachex.Actions.SaveTest do
  use Cachex.Test.Case

  # This test covers the backing up of a cache to a local disk location. We only
  # cover the happy path as there are separate tests covering issues with the
  # path provided to the save. We set a value, save to disk, then clear the cache.
  # We then load the backup file to verify that the values come back.
  test "saving a cache to a local disk" do
    # locate the temporary directory
    tmp = System.tmp_dir!()

    # create a test cache
    cache = TestUtils.create_cache()

    # add some cache entries
    assert Cachex.put(cache, 1, 1) == {:ok, true}

    # create a local path to write to
    path = Path.join(tmp, TestUtils.gen_rand_bytes(8))

    # save the cache to a local file
    assert Cachex.save(cache, path)

    # verify the result and clearance
    assert Cachex.clear(cache) == 1
    assert Cachex.size(cache) == 0

    # load the cache from the disk
    assert Cachex.restore(cache, path) == 1

    # verify that the load was ok
    assert Cachex.size(cache) == 1
  end

  # This test covers the backing up of a cache cluster to a local disk location. We
  # basically copy the local example, except that we run it against a cluster with
  # several nodes - the entire cluster should be backed up to the local disk.
  @tag distributed: true
  test "backing up a cache cluster to a local disk" do
    # locate the temporary directory
    tmp = System.tmp_dir!()

    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    assert Cachex.put(cache, 1, 1) == {:ok, true}
    assert Cachex.put(cache, 2, 2) == {:ok, true}

    # create a local path to write to
    path1 = Path.join(tmp, TestUtils.gen_rand_bytes(8))
    path2 = Path.join(tmp, TestUtils.gen_rand_bytes(8))

    # save the cache to a local file for local/remote
    assert Cachex.save(cache, path1, local: true)
    assert Cachex.save(cache, path2, local: false)

    # clear the cache to remove all
    assert Cachex.clear(cache) == 2

    # load the local cache from the disk
    assert Cachex.restore(cache, path1) == 1
    assert Cachex.size(cache) == 1

    # clear the cache again
    assert Cachex.clear(cache) == 1

    # load the full cache from the disk
    assert Cachex.restore(cache, path2) == 2
    assert Cachex.size(cache) == 2
  end

  test "returning an error on invalid output path" do
    # create a test cache
    cache = TestUtils.create_cache()

    # verify that saving to the invalid path gives an error
    assert Cachex.save(cache, "") == {:error, :unreachable_file}
  end
end
