defmodule Cachex.Actions.FetchTest do
  use CachexCase

  # This test verifies that we can retrieve keys from the cache with the
  # ability to compute values if they're missing. If a key has expired,
  # the value is not returned and the hooks are updated with an eviction.
  # If the provided function is arity 1, we ignore the state argument.
  test "fetching keys from a cache" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a default fetch action
    concat = &(&1 <> "_" <> &2)

    # create a test cache
    cache1 = Helper.create_cache([ hooks: [ hook ] ])
    cache2 = Helper.create_cache([
      hooks: [ hook ],
      fallback: fallback(state: "val", default: concat)
    ])

    # set some keys in the cache
    { :ok, true } = Cachex.put(cache1, "key1", 1)
    { :ok, true } = Cachex.put(cache1, "key2", 2, ttl: 1)

    # wait for the TTL to pass
    :timer.sleep(2)

    # flush all existing messages
    Helper.flush()

    # define the fallback options
    fb_opt1 = &String.reverse/1
    fb_opt2 = &({ :commit, String.reverse(&1) })
    fb_opt3 = &({ :ignore, String.reverse(&1) })
    fb_opt4 = fn -> "6yek" end

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
    result6 = Cachex.fetch(cache1, "key6", fb_opt4)

    # verify the fallback fetches
    assert(result3 == { :commit, "3yek" })
    assert(result4 == { :commit, "4yek" })
    assert(result5 == { :ignore, "5yek" })
    assert(result6 == { :commit, "6yek" })

    # test using a default fallback state
    result7 = Cachex.fetch(cache2, "key7")

    # verify that it executes and ignores state
    assert(result7 == { :commit, "key7_val" })

    # assert we receive valid notifications
    assert_receive({ { :fetch, [ "key1", ^fb_opt1, [ ] ] }, ^result1 })
    assert_receive({ { :fetch, [ "key2", ^fb_opt1, [ ] ] }, ^result2 })
    assert_receive({ { :fetch, [ "key3", ^fb_opt1, [ ] ] }, ^result3 })
    assert_receive({ { :fetch, [ "key4", ^fb_opt2, [ ] ] }, ^result4 })
    assert_receive({ { :fetch, [ "key5", ^fb_opt3, [ ] ] }, ^result5 })
    assert_receive({ { :fetch, [ "key6", ^fb_opt4, [ ] ] }, ^result6 })
    assert_receive({ { :fetch, [ "key7",  ^concat, [ ] ] }, ^result7 })

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
    assert(value3 == { :ok, nil })

    # check using a missing fallback
    result8 = Cachex.fetch(cache1, "key7")
    result9 = Cachex.fetch(cache1, "key8", "val")

    # both should be an error for invalid function
    assert(result8 == { :error, :invalid_fallback })
    assert(result9 == { :error, :invalid_fallback })
  end

  # This test ensures that the fallback is executed just once when a
  # fallback commit and another fetch on the same key occur simultaneously.
  test "fetching and committing the same key simultaneously from a fallback" do
    for _ <- 1..10 do
      cache = Helper.create_cache()

      key1_fallback = fn ->
        Cachex.incr!(cache, "key1_fallback_count")
        { :commit, "val" }
      end
      task1 = Task.async(fn -> Cachex.fetch(cache, "key1", key1_fallback) end)

      # Run task2 with a fetch on key2 just as a means to fetch key1
      # at the exact same time that task1 is committing it.
      key2_fallback = fn ->
        # incr! this key here just to match key1_fallback's execution time
        Cachex.incr!(cache, "key2_fallback_count")
        Cachex.fetch(cache, "key1", key1_fallback)
      end
      task2 = Task.async(fn -> Cachex.fetch(cache, "key2", key2_fallback) end)

      Task.await(task1)
      Task.await(task2)
      { :ok, fallback_count } = Cachex.get(cache, "key1_fallback_count")
      assert(fallback_count == 1)
    end
  end
end
