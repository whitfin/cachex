defmodule Cachex.Services.JanitorTest do
  use CachexCase

  # The Janitor process can run on a schedule too, to automatically purge records.
  # This test should verify a Janitor running on a schedule, as well as make sure
  # that the Janitor sends a notification to hooks whenever the process removes
  # some keys, as Janitor actions should be subscribable. This test will als
  # verify that the metadata of the last run is updated alongside the changes.
  test "purging records on a schedule" do
    # create our forwarding hook
    hooks = ForwardHook.create()

    # set our interval values
    ttl_interval = 50
    ttl_value = div(ttl_interval, 2)
    ttl_wait = round(ttl_interval * 1.5)

    # create a test cache
    cache = Helper.create_cache([ hooks: hooks, expiration: expiration(interval: ttl_interval) ])
    cache = Services.Overseer.retrieve(cache)

    # add a new cache entry
    { :ok, true } = Cachex.set(cache, "key", "value", ttl: ttl_value)

    # check that the key exists
    exists1 = Cachex.exists?(cache, "key")

    # before the schedule, the key should exist
    assert(exists1 == { :ok, true })

    # wait for the schedule
    :timer.sleep(ttl_wait)

    # check that the key exists
    exists2 = Cachex.exists?(cache, "key")

    # the key should have been removed
    assert(exists2 == { :ok, false })

    # retrieve the metadata
    { :ok, metadata1 } = Services.Janitor.last_run(cache)

    # verify the count was updated
    assert(metadata1[:count] == 1)

    # verify the duration is valid
    assert(is_integer(metadata1[:duration]))

    # windows will round to nearest millis (0)
    assert(metadata1[:duration] >= 0)

    # verify the start time was set
    assert(is_integer(metadata1[:started]))
    assert(metadata1[:started] > 0)
    assert(metadata1[:started] <= :os.system_time(:milli_seconds))

    # ensure we receive(d) the hook notification
    assert_receive({ { :purge, [[]] }, { :ok, 1 } })
  end
end
