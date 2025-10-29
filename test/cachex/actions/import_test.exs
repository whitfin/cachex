defmodule Cachex.Actions.ImportTest do
  use Cachex.Test.Case

  # This test verifies that it's possible to import entries into a cache.
  test "importing records into a cache" do
    # create a test cache
    cache = TestUtils.create_cache()
    start = now()

    # add some cache entries
    assert Cachex.put(cache, 1, 1) == {:ok, true}
    assert Cachex.put(cache, 2, 2, expire: 1) == {:ok, true}
    assert Cachex.put(cache, 3, 3, expire: 10_000) == {:ok, true}

    # export the cache to a list
    result1 = Cachex.export(cache)

    # verify the clearance
    assert Cachex.clear(cache) == 3
    assert Cachex.size(cache) == 0

    # wait a while before re-load
    :timer.sleep(50)

    # load the cache from the export
    assert Cachex.import(cache, result1) == 2
    assert Cachex.size(cache) == 2

    # verify TTL offsetting happens
    cache
    |> Cachex.ttl(3)
    |> assert_in_delta(10_000 - (now() - start), 5)
  end
end
