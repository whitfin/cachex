defmodule Cachex.Hook.StatsTest do
  use CachexCase

  # There's nothing more to test inside this hook beyond the ability to retrieve
  # the current state of the hook, and validate what it looks like after a couple
  # of stats have been incremented. Incrementation is done via the Cachex.Stats
  # module, so please refer to those tests for any issues with counters.
  test "retrieving the state of a hook" do
    # create a test cache
    cache = Helper.create_cache([ stats: true ])

    # retrieve the current time
    ctime = now()

    # carry out some cache operations
    { :ok, true } = Cachex.set(cache, 1, 1)
    { :ok,    1 } = Cachex.get(cache, 1)

    # generate the name of the stats hook
    sname = name(cache, :stats)

    # attempt to retrieve the cache stats
    stats = Cachex.Hook.Stats.retrieve(sname)

    # verify the state of the stats
    assert_in_delta(stats.meta.creationDate, ctime, 5)
    assert(stats.get == %{ ok: 1 })
    assert(stats.global == %{ hitCount: 1, opCount: 2, setCount: 1 })
    assert(stats.set == %{ true: 1 })
  end
end
