defmodule Cachex.Actions.GetAndUpdateTest do
  use CachexCase

  # This test verifies that we can retrieve and update cache values. We make sure
  # to check the ability to ignore a value rather than committing, as well as the
  # TTL of a key being maintained after the update calls.
  test "retrieving and updated cache records" do
    # create a forwarding hook
    hook = ForwardHook.create(%{ results: true })

    # create a test cache
    cache = Helper.create_cache([ hooks: [ hook ] ])

    # set some keys in the cache
    { :ok, true } = Cachex.set(cache, 1, 1)
    { :ok, true } = Cachex.set(cache, 2, 2, ttl: 1)
    { :ok, true } = Cachex.set(cache, 5, 5, ttl: 1000)
    { :ok, true } = Cachex.set(cache, 6, 6)
    { :ok, true } = Cachex.set(cache, 7, 7)

    # wait for the TTL to pass
    :timer.sleep(25)

    # flush all existing messages
    Helper.flush()

    # update the first and second keys
    result1 = Cachex.get_and_update(cache, 1, &to_string/1)
    result2 = Cachex.get_and_update(cache, 2, &to_string/1)

    # update a missing key
    result3 = Cachex.get_and_update(cache, 3, &to_string/1)

    # define the fallback options
    fb_opts = [ fallback: fn(key) ->
      "_#{key}_"
    end ]

    # update a fallback key
    result4 = Cachex.get_and_update(cache, 4, &to_string/1, fb_opts)

    # update the fifth value
    result5 = Cachex.get_and_update(cache, 5, &to_string/1)

    # update the sixth value (but with no commit)
    result6 = Cachex.get_and_update(cache, 6, fn(_) ->
      { :ignore, "7" }
    end)

    # update the seventh value (with a commit)
    result7 = Cachex.get_and_update(cache, 7, fn(_) ->
      { :commit, "7" }
    end)

    # verify the first key is retrieved
    assert(result1 == { :ok, "1" })

    # verify the second and third keys are missing
    assert(result2 == { :missing, "" })
    assert(result3 == { :missing, "" })

    # verify the fourth key uses the fallback
    assert(result4 == { :loaded, "_4_" })

    # verify the fifth result
    assert(result5 == { :ok, "5" })

    # verify the sixth and seventh results
    assert(result6 == { :ok, "7" })
    assert(result7 == { :ok, "7" })

    # assert we receive valid notifications
    assert_receive({ { :get_and_update, [ 1, _to_string, [ ] ] }, ^result1 })
    assert_receive({ { :get_and_update, [ 2, _to_string, [ ] ] }, ^result2 })
    assert_receive({ { :get_and_update, [ 3, _to_string, [ ] ] }, ^result3 })
    assert_receive({ { :get_and_update, [ 4, _to_string, ^fb_opts ] }, ^result4 })
    assert_receive({ { :get_and_update, [ 5, _to_string, [ ] ] }, ^result5 })
    assert_receive({ { :get_and_update, [ 6, _my_functs, [ ] ] }, ^result6 })
    assert_receive({ { :get_and_update, [ 7, _my_functs, [ ] ] }, ^result7 })

    # check we received valid purge actions for the TTL
    assert_receive({ { :purge, [[]] }, { :ok, 1 } })

    # retrieve all entries from the cache
    value1 = Cachex.get(cache, 1)
    value2 = Cachex.get(cache, 2)
    value3 = Cachex.get(cache, 3)
    value4 = Cachex.get(cache, 4)
    value5 = Cachex.get(cache, 5)
    value6 = Cachex.get(cache, 6)
    value7 = Cachex.get(cache, 7)

    # all should now have values
    assert(value1 == { :ok, "1" })
    assert(value2 == { :ok, "" })
    assert(value3 == { :ok, "" })
    assert(value4 == { :ok, "_4_" })
    assert(value5 == { :ok, "5" })

    # verify the commit tags
    assert(value6 == { :ok, 6 })
    assert(value7 == { :ok, "7" })

    # check the TTL on the last key
    ttl1 = Cachex.ttl!(cache, 5)

    # TTL should be maintained
    assert_in_delta(ttl1, 965, 11)
  end

end
