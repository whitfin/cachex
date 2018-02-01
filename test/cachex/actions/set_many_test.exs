defmodule Cachex.Actions.SetManyTest do
  use CachexCase

  # This test just covers the case of forwarding calls
  # to set_many() through to put_many() in order to
  # validate the backwards compatibility calls.
  test "forwarding calls to put_many(2/3)" do
    # create a test cache
    cache = Helper.create_cache()

    # set values in the cache
    result1 = Cachex.set_many(cache, [ { 1, 1 }, { 2, 2 } ])
    result2 = Cachex.set_many(cache, [ { 3, 3 }, { 4, 4 } ], [ ttl: 5000 ])

    # verify the results of the writes
    assert(result1 == { :ok, true })
    assert(result2 == { :ok, true })

    # retrieve the written value
    result2 = Cachex.get(cache, 1)
    result3 = Cachex.get(cache, 2)
    result4 = Cachex.get(cache, 3)
    result5 = Cachex.get(cache, 4)

    # check that it was written
    assert(result2 == { :ok, 1 })
    assert(result3 == { :ok, 2 })
    assert(result4 == { :ok, 3 })
    assert(result5 == { :ok, 4 })

    # check the ttl on the last calls
    result6 = Cachex.ttl!(cache, 3)
    result7 = Cachex.ttl!(cache, 4)

    # the second should have a TTL around 5s
    assert_in_delta(result6, 5000, 10)
    assert_in_delta(result7, 5000, 10)
  end
end
