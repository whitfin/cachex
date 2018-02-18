defmodule Cachex.Actions.TtlTest do
  use CachexCase

  # This test verifies the responses of checking TTLs inside the cache. We make
  # sure that TTLs are calculated correctly based on nil and set TTLs. If the
  # key is missing, we return a tuple signalling such.
  test "retrieving a key TTL" do
    # create a test cache
    cache = Helper.create_cache()

    # set several keys in the cache
    { :ok, true } = Cachex.put(cache, 1, 1)
    { :ok, true } = Cachex.put(cache, 2, 2, ttl: 10000)

    # verify the TTL of both keys
    ttl1 = Cachex.ttl(cache, 1)
    ttl2 = Cachex.ttl!(cache, 2)

    # verify the TTL of a missing key
    ttl3 = Cachex.ttl(cache, 3)

    # the first TTL should be nil
    assert(ttl1 == { :ok, nil })

    # the second should be close to 10s
    assert_in_delta(ttl2, 10000, 10)

    # the third should return a missing value
    assert(ttl3 == { :ok, nil })
  end
end
