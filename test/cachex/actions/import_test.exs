defmodule Cachex.Actions.ImportTest do
  use Cachex.Test.Case

  # This test verifies that it's possible to import entries into a cache.
  test "importing records into a cache" do
    # create a test cache
    cache = TestUtils.create_cache()
    start = now()

    # add some cache entries
    {:ok, true} = Cachex.put(cache, 1, 1)
    {:ok, true} = Cachex.put(cache, 2, 2, expire: 1)
    {:ok, true} = Cachex.put(cache, 3, 3, expire: 10_000)

    # export the cache to a list
    result1 = Cachex.export(cache)
    result2 = Cachex.clear(cache)
    result3 = Cachex.size(cache)

    # verify the clearance
    assert(result2 == {:ok, 3})
    assert(result3 == {:ok, 0})

    # wait a while before re-load
    :timer.sleep(50)

    # load the cache from the export
    result4 = Cachex.import(cache, elem(result1, 1))
    result5 = Cachex.size(cache)
    result6 = Cachex.ttl!(cache, 3)

    # verify that the import was ok
    assert(result4 == {:ok, 2})
    assert(result5 == {:ok, 2})

    # verify TTL offsetting happens
    assert_in_delta(result6, 10_000 - (now() - start), 5)
  end
end
