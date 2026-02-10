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
    assert Cachex.put(cache, 1, 1) == :ok
    assert Cachex.put(cache, 2, 2, expire: 1) == :ok
    assert Cachex.put(cache, 3, 3, expire: 10_000) == :ok

    # create a local path to write to
    path = Path.join(tmp, TestUtils.gen_rand_bytes(8))

    # save the cache to a local file
    assert Cachex.save(cache, path) == :ok

    # verify the result and clearance
    assert Cachex.clear(cache) == 3
    assert Cachex.size(cache) == 0

    # wait a while before re-load
    :timer.sleep(50)

    # load the cache from the disk
    assert Cachex.restore(cache, path) == 2
    assert Cachex.size(cache) == 2

    # verify TTL offsetting happens
    assert_in_delta Cachex.ttl(cache, 3), 10_000 - (now() - start), 5

    # reload a bad file from disk (should not be trusted)
    assert Cachex.restore(cache, tmp, trust: false) == {:error, :eisdir}
  end
end
