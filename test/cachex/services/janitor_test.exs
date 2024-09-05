defmodule Cachex.Services.JanitorTest do
  use Cachex.Test.Case

  # We have a common utility to check whether a TTL has passed or not based on
  # an input of a write time and a TTL length. This test ensures that this returns
  # true or false based on whether we should expire or not. There's also additional
  # logic that a cache can have expiration disabled, and so if we pass a state with
  # it disabled, it should return false regardless of the date deltas.
  test "checking whether an expiration has passed" do
    # this combination has expired
    modified1 = 5000
    expiration1 = 5000

    # this combination has not
    modified2 = :os.system_time(:milli_seconds)
    expiration2 = 100_000_000

    # define both an enabled and disabled state
    state1 = cache(expiration: expiration(lazy: true))
    state2 = cache(expiration: expiration(lazy: false))

    # expired combination regardless of state
    result1 =
      Services.Janitor.expired?(
        entry(modified: modified1, expiration: expiration1)
      )

    # unexpired combination regardless of state
    result2 =
      Services.Janitor.expired?(
        entry(modified: modified2, expiration: expiration2)
      )

    # expired combination with state enabled
    result3 =
      Services.Janitor.expired?(
        state1,
        entry(modified: modified1, expiration: expiration1)
      )

    # expired combination with state disabled
    result4 =
      Services.Janitor.expired?(
        state2,
        entry(modified: modified1, expiration: expiration1)
      )

    # only the first and third should have expired
    assert(result1)
    assert(result3)

    # the second and fourth should not have
    refute(result2)
    refute(result4)
  end

  # The Janitor process can run on a schedule too, to automatically purge records.
  # This test should verify a Janitor running on a schedule, as well as make sure
  # that the Janitor sends a notification to hooks whenever the process removes
  # some keys, as Janitor actions should be subscribable. This test will also
  # verify that the metadata of the last run is updated alongside the changes.
  test "purging records on a schedule" do
    # create our forwarding hook
    hooks = ForwardHook.create()

    # set our interval values
    ttl_interval = 50
    ttl_value = div(ttl_interval, 2)
    ttl_wait = round(ttl_interval * 1.5)

    # create a test cache
    cache =
      TestUtils.create_cache(
        hooks: hooks,
        expiration: expiration(interval: ttl_interval)
      )

    cache = Services.Overseer.retrieve(cache)

    # add a new cache entry
    {:ok, true} = Cachex.put(cache, "key", "value", expiration: ttl_value)

    # check that the key exists
    exists1 = Cachex.exists?(cache, "key")

    # before the schedule, the key should exist
    assert(exists1 == {:ok, true})

    # wait for the schedule
    :timer.sleep(ttl_wait)

    # check that the key exists
    exists2 = Cachex.exists?(cache, "key")

    # the key should have been removed
    assert(exists2 == {:ok, false})

    # retrieve the metadata
    {:ok, metadata1} = Services.Janitor.last_run(cache)

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
    assert_receive({{:purge, [[]]}, {:ok, 1}})
  end
end
