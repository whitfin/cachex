defmodule Cachex.Services.JanitorTest do
  use CachexCase

  # The Janitor module provides a public function for use by external processes
  # which wish to purge expired records. This function simply purges expired
  # records and returns the count of removed records. This test simply verifies
  # the number returned here and that the records are indeed removed.
  test "purging records manually" do
    # create a test cache
    cache = Helper.create_cache()

    # fetch the state
    state = Services.Overseer.get(cache)

    # add a new cache entry
    { :ok, true } = Cachex.set(state, "key", "value", ttl: 25)

    # purge before the entry expires
    purge1 = Services.Janitor.purge_records(state)

    # verify that the purge removed nothing
    assert(purge1 == { :ok, 0 })

    # wait until the entry has expired
    :timer.sleep(50)

    # purge after the entry expires
    purge2 = Services.Janitor.purge_records(state)

    # verify that the purge removed the key
    assert(purge2 == { :ok, 1 })

    # check whether the key exists
    exists = Cachex.exists?(state, "key")

    # verify that the key is gone
    assert(exists == { :ok, false })
  end

  # The Janitor process can run on a schedule too, to automatically purge records.
  # This test should verify a Janitor running on a schedule, as well as make sure
  # that the Janitor sends a notification to hooks whenever the process removes
  # some keys, as Janitor actions should be subscribable. This test will als
  # verify that the metadata of the last run is updated alongside the changes.
  test "purging records on a schedule" do
    # create our forwarding hook
    hooks = ForwardHook.create(%{
      results: true
    })

    # set our interval values
    ttl_interval = 50
    ttl_value = div(ttl_interval, 2)
    ttl_wait = round(ttl_interval * 1.5)

    # create a test cache
    cache = Helper.create_cache([ hooks: hooks, ttl_interval: ttl_interval ])

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
    metadata1 = GenServer.call(name(cache, :janitor), :last)

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
