defmodule Cachex.Actions.SetTest do
  use CachexCase

  # This test verifies the addition of new entries to the cache. We ensure that
  # values can be added and can be given expiration values. We also test the case
  # in which a cache has a default expiration value, and the ability to override
  # this as necessary.
  test "adding new values to the cache" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache1 = Helper.create_cache([ hooks: [ hook ] ])

    # create a test cache with a default ttl
    cache2 = Helper.create_cache([ hooks: [ hook ], default_ttl: 10000 ])

    # set some values in the cache
    set1 = Cachex.set(cache1, 1, 1)
    set2 = Cachex.set(cache1, 2, 2, ttl: 5000)
    set3 = Cachex.set(cache2, 1, 1)
    set4 = Cachex.set(cache2, 2, 2, ttl: 5000)

    # ensure all set actions worked
    assert(set1 == { :ok, true })
    assert(set2 == { :ok, true })
    assert(set3 == { :ok, true })
    assert(set4 == { :ok, true })

    # verify the hooks were updated with the message
    assert_receive({ { :set, [ 1, 1, [] ] }, ^set1 })
    assert_receive({ { :set, [ 1, 1, [] ] }, ^set3 })
    assert_receive({ { :set, [ 2, 2, [ ttl: 5000 ] ] }, ^set2 })
    assert_receive({ { :set, [ 2, 2, [ ttl: 5000 ] ] }, ^set4 })

    # read back all values from the cache
    value1 = Cachex.get(cache1, 1)
    value2 = Cachex.get(cache1, 2)
    value3 = Cachex.get(cache2, 1)
    value4 = Cachex.get(cache2, 2)

    # verify all values exist
    assert(value1 == { :ok, 1 })
    assert(value2 == { :ok, 2 })
    assert(value3 == { :ok, 1 })
    assert(value4 == { :ok, 2 })

    # read back all key TTLs
    ttl1 = Cachex.ttl!(cache1, 1)
    ttl2 = Cachex.ttl!(cache1, 2)
    ttl3 = Cachex.ttl!(cache2, 1)
    ttl4 = Cachex.ttl!(cache2, 2)

    # the first should have no TTL
    assert(ttl1 == nil)

    # the second should have a TTL around 5s
    assert_in_delta(ttl2, 5000, 10)

    # the second should have a TTL around 10s
    assert_in_delta(ttl3, 10000, 10)

    # the fourth should have a TTL around 5s
    assert_in_delta(ttl4, 5000, 10)
  end
end
