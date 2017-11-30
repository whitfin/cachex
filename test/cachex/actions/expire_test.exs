defmodule Cachex.Actions.ExpireTest do
  use CachexCase

  # This test updates the expire time on a key to expire after a given period.
  # We make sure that TTLs are updated accordingly. If the period is negative,
  # the key is immediately removed. We also make sure that we can handle setting
  # expire times on missing keys.
  test "setting a key to expire after a given period" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = Helper.create_cache([ hooks: [ hook ] ])

    # add some keys to the cache
    { :ok, true } = Cachex.set(cache, 1, 1)
    { :ok, true } = Cachex.set(cache, 2, 2, ttl: 10)
    { :ok, true } = Cachex.set(cache, 3, 3, ttl: 10)

    # clear messages
    Helper.flush()

    # set the expire time
    f_expire_time =  10000
    p_expire_time = -10000

    # expire several keys
    result1 = Cachex.expire(cache, 1, f_expire_time)
    result2 = Cachex.expire(cache, 2, f_expire_time)
    result3 = Cachex.expire(cache, 3, p_expire_time)
    result4 = Cachex.expire(cache, 4, f_expire_time)

    # the first two should succeed
    assert(result1 == { :ok, true })
    assert(result2 == { :ok, true })

    # the third should succeed and remove the key
    assert(result3 == { :ok, true })

    # the last one is missing and should fail
    assert(result4 == { :missing, false })

    # verify the hooks were updated with the message
    assert_receive({ { :expire, [ 1, ^f_expire_time, [] ] }, ^result1 })
    assert_receive({ { :expire, [ 2, ^f_expire_time, [] ] }, ^result2 })
    assert_receive({ { :expire, [ 3, ^p_expire_time, [] ] }, ^result3 })
    assert_receive({ { :expire, [ 4, ^f_expire_time, [] ] }, ^result4 })

    # check we received valid purge actions for the removed key
    assert_receive({ { :purge, [[]] }, { :ok, 1 } })

    # retrieve all TTLs from the cache
    ttl1 = Cachex.ttl!(cache, 1)
    ttl2 = Cachex.ttl!(cache, 2)
    ttl3 = Cachex.ttl(cache, 3)
    ttl4 = Cachex.ttl(cache, 4)

    # verify the new TTL has taken effect
    assert_in_delta(ttl1, 10000, 25)
    assert_in_delta(ttl2, 10000, 25)

    # assert the last two keys don't exist
    assert(ttl3 == { :missing, nil })
    assert(ttl4 == { :missing, nil })
  end
end
