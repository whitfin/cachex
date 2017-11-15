defmodule Cachex.Actions.FetchTest do
  use CachexCase

  # This test verifies that we can retrieve keys from the cache with the
  # ability to compute values if they're missing. If a key has expired,
  # the value is not returned and the hooks are updated with an eviction.
  # If the provided function is arity 1, we ignore the state argument.
  test "fetching keys from a cache" do
    # create a forwarding hook
    hook = ForwardHook.create(%{ results: true })

    # create a default fetch action
    concat = &(&1 <> "_" <> &2)

    # create a test cache
    cache1 = Helper.create_cache([ hooks: [ hook ] ])
    cache2 = Helper.create_cache([
      hooks: [ hook ],
      fallback: [
        state: "val",
        action: concat
      ]
    ])

    # set some keys in the cache
    { :ok, true } = Cachex.set(cache1, "key1", 1)
    { :ok, true } = Cachex.set(cache1, "key2", 2, ttl: 1)

    # wait for the TTL to pass
    :timer.sleep(2)

    # flush all existing messages
    Helper.flush()

    # define the fallback options
    fb_opt1 = &String.reverse/1
    fb_opt2 = &({ :commit, String.reverse(&1) })
    fb_opt3 = &({ :ignore, String.reverse(&1) })

    # fetch the first and second keys
    result1 = Cachex.fetch(cache1, "key1", fb_opt1)
    result2 = Cachex.fetch(cache1, "key2", fb_opt1)

    # verify fetching an existing key
    assert(result1 == { :ok, 1 })

    # verify the ttl expiration
    assert(result2 == { :commit, "2yek" })

    # fetch keys with a provided fallback
    result3 = Cachex.fetch(cache1, "key3", fb_opt1)
    result4 = Cachex.fetch(cache1, "key4", fb_opt2)
    result5 = Cachex.fetch(cache1, "key5", fb_opt3)

    # verify the fallback fetches
    assert(result3 == { :commit, "3yek" })
    assert(result4 == { :commit, "4yek" })
    assert(result5 == { :ignore, "5yek" })

    # test using a default fallback state
    result6 = Cachex.fetch(cache2, "key6")

    # verify that it executes and ignores state
    assert(result6 == { :commit, "key6_val" })

    # assert we receive valid notifications
    assert_receive({ { :fetch, [ "key1", ^fb_opt1, [ ] ] }, ^result1 })
    assert_receive({ { :fetch, [ "key2", ^fb_opt1, [ ] ] }, ^result2 })
    assert_receive({ { :fetch, [ "key3", ^fb_opt1, [ ] ] }, ^result3 })
    assert_receive({ { :fetch, [ "key4", ^fb_opt2, [ ] ] }, ^result4 })
    assert_receive({ { :fetch, [ "key5", ^fb_opt3, [ ] ] }, ^result5 })
    assert_receive({ { :fetch, [ "key6",  ^concat, [ ] ] }, ^result6 })

    # check we received valid purge actions for the TTL
    assert_receive({ { :purge, [[]] }, { :ok, 1 } })

    # retrieve the loaded keys
    value1 = Cachex.get(cache1, "key3")
    value2 = Cachex.get(cache1, "key4")
    value3 = Cachex.get(cache1, "key5")

    # committed keys should now exist
    assert(value1 == { :ok, "3yek" })
    assert(value2 == { :ok, "4yek" })

    # ignored keys should not exist
    assert(value3 == { :missing, nil })

    # check using a missing fallback
    result7 = Cachex.fetch(cache1, "key7")
    result8 = Cachex.fetch(cache1, "key8", "val")

    # both should be an error for invalid function
    assert(result7 == { :error, :invalid_fallback })
    assert(result8 == { :error, :invalid_fallback })
  end
end
