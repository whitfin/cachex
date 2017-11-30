defmodule Cachex.Actions.PurgeTest do
  use CachexCase

  # This test makes sure that we can manually purge expired records from the cache.
  # We attempt to purge before a key has expired and verify that it has not been
  # removed. We then wait until after the TTL has passed and ensure that it is
  # removed by the purge call. Finally we make sure to check the hook notifications.
  test "purging expired records" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = Helper.create_cache([ hooks: [ hook ] ])

    # add a new cache entry
    { :ok, true } = Cachex.set(cache, "key", "value", ttl: 25)

    # flush messages
    Helper.flush()

    # purge before the entry expires
    purge1 = Cachex.purge(cache)

    # verify that the purge removed nothing
    assert(purge1 == { :ok, 0 })

    # ensure we received a message
    assert_receive({ { :purge, [[]] }, { :ok, 0 } })

    # wait until the entry has expired
    :timer.sleep(50)

    # purge after the entry expires
    purge2 = Cachex.purge(cache)

    # verify that the purge removed the key
    assert(purge2 == { :ok, 1 })

    # ensure we received a message
    assert_receive({ { :purge, [[]] }, { :ok, 1 } })

    # check whether the key exists
    exists = Cachex.exists?(cache, "key")

    # verify that the key is gone
    assert(exists == { :ok, false })
  end
end
