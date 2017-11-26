defmodule Cachex.Actions.SizeTest do
  use CachexCase

  # This test verifies the size of a cache. It should be noted that size is the
  # total size of the cache, regardless of any evictions (unlike count). We make
  # sure that evictions aren't taken into account, and that size increments as
  # new keys are added to the cache.
  test "checking the total size of a cache" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = Helper.create_cache([ hooks: [ hook ] ])

    # retrieve the cache size
    result1 = Cachex.size(cache)

    # it should be empty
    assert(result1 == { :ok, 0 })

    # verify the hooks were updated with the message
    assert_receive({ { :size, [[]] }, ^result1 })

    # add some cache entries
    { :ok, true } = Cachex.set(cache, 1, 1)

    # retrieve the cache size
    result2 = Cachex.size(cache)

    # it should show the new key
    assert(result2 == { :ok, 1 })

    # verify the hooks were updated with the message
    assert_receive({ { :size, [[]] }, ^result2 })

    # add a final entry
    { :ok, true } = Cachex.set(cache, 2, 2, ttl: 1)

    # let it expire
    :timer.sleep(2)

    # retrieve the cache size
    result3 = Cachex.size(cache)

    # it shouldn't care about TTL
    assert(result3 == { :ok, 2 })

    # verify the hooks were updated with the message
    assert_receive({ { :size, [[]] }, ^result3 })
  end
end
