defmodule Cachex.Actions.GetAndUpdateTest do
  use CachexCase

  # This test verifies that we can retrieve and update cache values. We make sure
  # to check the ability to ignore a value rather than committing, as well as the
  # TTL of a key being maintained after the update calls.
  test "retrieving and updated cache records" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = Helper.create_cache([ hooks: [ hook ] ])

    # set some keys in the cache
    { :ok, true } = Cachex.put(cache, 1, 1)
    { :ok, true } = Cachex.put(cache, 2, 2, ttl: 1)
    { :ok, true } = Cachex.put(cache, 4, 4, ttl: 1000)
    { :ok, true } = Cachex.put(cache, 5, 5)
    { :ok, true } = Cachex.put(cache, 6, 6)

    # wait for the TTL to pass
    :timer.sleep(25)

    # flush all existing messages
    Helper.flush()

    # update the first and second keys
    result1 = Cachex.get_and_update(cache, 1, &to_string/1)
    result2 = Cachex.get_and_update(cache, 2, &to_string/1)

    # update a missing key
    result3 = Cachex.get_and_update(cache, 3, &to_string/1)

    # update the fourth value
    result4 = Cachex.get_and_update(cache, 4, &to_string/1)

    # update the fifth value (but with no commit)
    result5 = Cachex.get_and_update(cache, 5, fn(_) ->
      { :ignore, "5" }
    end)

    # update the sixth value (with a commit)
    result6 = Cachex.get_and_update(cache, 6, fn(_) ->
      { :commit, "6" }
    end)

    # verify the first key is retrieved
    assert(result1 == { :ok, "1" })

    # verify the second and third keys are missing
    assert(result2 == { :missing, "" })
    assert(result3 == { :missing, "" })

    # verify the fourth result
    assert(result4 == { :ok, "4" })

    # verify the fifth and sixth results
    assert(result5 == { :ok, "5" })
    assert(result6 == { :ok, "6" })

    # assert we receive valid notifications
    assert_receive({ { :get_and_update, [ 1, _to_string, [ ] ] }, ^result1 })
    assert_receive({ { :get_and_update, [ 2, _to_string, [ ] ] }, ^result2 })
    assert_receive({ { :get_and_update, [ 3, _to_string, [ ] ] }, ^result3 })
    assert_receive({ { :get_and_update, [ 4, _to_string, [ ] ] }, ^result4 })
    assert_receive({ { :get_and_update, [ 5, _my_functs, [ ] ] }, ^result5 })
    assert_receive({ { :get_and_update, [ 6, _my_functs, [ ] ] }, ^result6 })

    # check we received valid purge actions for the TTL
    assert_receive({ { :purge, [[]] }, { :ok, 1 } })

    # retrieve all entries from the cache
    value1 = Cachex.get(cache, 1)
    value2 = Cachex.get(cache, 2)
    value3 = Cachex.get(cache, 3)
    value4 = Cachex.get(cache, 4)
    value5 = Cachex.get(cache, 5)
    value6 = Cachex.get(cache, 6)

    # all should now have values
    assert(value1 == { :ok, "1" })
    assert(value2 == { :ok, "" })
    assert(value3 == { :ok, "" })
    assert(value4 == { :ok, "4" })

    # verify the commit tags
    assert(value5 == { :ok, 5 })
    assert(value6 == { :ok, "6" })

    # check the TTL on the last key
    ttl1 = Cachex.ttl!(cache, 4)

    # TTL should be maintained
    assert_in_delta(ttl1, 965, 11)
  end
end
