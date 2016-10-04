defmodule Cachex.Actions.GetTest do
  use CachexCase

  # This test verifies that we can retrieve keys from the cache. If a key has expired,
  # the value is not returned and the hooks are updated with an eviction. If the
  # key is missing, we return a message stating as such.
  test "retrieving keys from a cache" do
    # create a forwarding hook
    hook = ForwardHook.create(%{ results: true })

    # create a test cache
    cache1 = Helper.create_cache([ hooks: [ hook ] ])
    cache2 = Helper.create_cache([
      hooks: [ hook ],
      fallback: [
        state: "val",
        action: &String.reverse("#{&1}_#{&2}")
      ]
    ])

    # set some keys in the cache
    { :ok, true } = Cachex.set(cache1, 1, 1)
    { :ok, true } = Cachex.set(cache1, 2, 2, ttl: 1)

    # wait for the TTL to pass
    :timer.sleep(2)

    # flush all existing messages
    Helper.flush()

    # take the first and second key
    result1 = Cachex.get(cache1, 1)
    result2 = Cachex.get(cache1, 2)

    # take a missing key with no fallback
    result3 = Cachex.get(cache1, 3)

    # define the fallback options
    fb_opts1 = [ fallback: &(&1 <> "_" <> &2) ]
    fb_opts2 = [ fallback: &({ :commit, &1 <> "_" <> &2 }) ]
    fb_opts3 = [ fallback: &({ :ignore, &1 <> "_" <> &2 }) ]

    # take keys with a fallback
    result4 = Cachex.get(cache2, "key1")
    result5 = Cachex.get(cache2, "key2", fb_opts1)
    result6 = Cachex.get(cache2, "key3", fb_opts2)
    result7 = Cachex.get(cache2, "key4", fb_opts3)

    # verify the first key is retrieved
    assert(result1 == { :ok, 1 })

    # verify the second and third keys are missing
    assert(result2 == { :missing, nil })
    assert(result3 == { :missing, nil })

    # verify the fourth key uses the default fallback
    assert(result4 == { :loaded, "lav_1yek" })

    # verify the fifth, sixth and seventh uses the custom fallback
    assert(result5 == { :loaded, "key2_val" })
    assert(result6 == { :loaded, "key3_val" })
    assert(result7 == { :loaded, "key4_val" })

    # assert we receive valid notifications
    assert_receive({ { :get, [ 1, [ ] ] }, ^result1 })
    assert_receive({ { :get, [ 2, [ ] ] }, ^result2 })
    assert_receive({ { :get, [ 3, [ ] ] }, ^result3 })
    assert_receive({ { :get, [ "key1", [ ] ] }, ^result4 })
    assert_receive({ { :get, [ "key2", ^fb_opts1 ] }, ^result5 })
    assert_receive({ { :get, [ "key3", ^fb_opts2 ] }, ^result6 })
    assert_receive({ { :get, [ "key4", ^fb_opts3 ] }, ^result7 })

    # check we received valid purge actions for the TTL
    assert_receive({ { :purge, [[]] }, { :ok, 1 } })

    # check if the expired key has gone
    exists1 = Cachex.exists?(cache1, 2)

    # it shouldn't exist
    assert(exists1 == { :ok, false })

    # retrieve the loaded keys
    value1 = Cachex.get(cache2, "key1")
    value2 = Cachex.get(cache2, "key2")
    value3 = Cachex.get(cache2, "key3")

    # both should now exist
    assert(value1 == { :ok, "lav_1yek" })
    assert(value2 == { :ok, "key2_val" })
    assert(value3 == { :ok, "key3_val" })

    # verify the :ignore response is not commited
    exists2 = Cachex.exists?(cache1, "key4")

    # it shouldn't exist
    assert(exists2 == { :ok, false })
  end

end
