defmodule Cachex.Actions.SetTest do
  use CachexCase

  # This test just covers the case of forwarding calls
  # to set() through to put() in order to validate the
  # backwards compatibility of the deprecated calls.
  test "forwarding calls to put(3/4)" do
    # create a test cache
    cache = Helper.create_cache()

    # set values in the cache
    result1 = Cachex.set(cache, 1, 1)
    result2 = Cachex.set(cache, 2, 2, [ ttl: 5000 ])

    # verify the results of the writes
    assert(result1 == { :ok, true })
    assert(result2 == { :ok, true })

    # retrieve the written value
    result2 = Cachex.get(cache, 1)
    result3 = Cachex.get(cache, 2)

    # check that it was written
    assert(result2 == { :ok, 1 })
    assert(result3 == { :ok, 2 })

    # check the ttl on the second call
    result4 = Cachex.ttl!(cache, 2)

    # the second should have a TTL around 5s
    assert_in_delta(result4, 5000, 10)
  end
end
