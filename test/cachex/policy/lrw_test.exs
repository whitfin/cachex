defmodule Cachex.Policy.LRWTest do
  use PowerAssert, async: false

  test "LRW doesn't evict with a nil upper bound" do
    limit = %Cachex.Limit{
      limit: nil,
      policy: Cachex.Policy.LRW,
      reclaim: 0.1
    }

    my_cache = TestHelper.create_cache([ limit: limit ])

    Cachex.execute(my_cache, fn(state) ->
      Enum.each(1..5000, fn(x) ->
        Cachex.set(state, x, x)
      end)
    end)

    assert(Cachex.size!(my_cache) == 5000)
  end

  test "LRW evicts the oldest entries when the limit is crossed" do
    limit = %Cachex.Limit{
      limit: 500,
      policy: Cachex.Policy.LRW,
      reclaim: 0.1
    }

    my_cache = TestHelper.create_cache([ max_size: limit ])

    Cachex.execute(my_cache, fn(state) ->
      Enum.each(1..500, fn(x) ->
        Cachex.set(state, x, x)
      end)
    end)

    assert(Cachex.size!(my_cache) == 500)

    Cachex.set(my_cache, 501, 501)

    TestHelper.poll(100, 450, fn ->
      Cachex.size!(my_cache)
    end)
  end

  test "LRW evicts a custom number of entries when the limit is crossed" do
    limit = %Cachex.Limit{
      limit: 500,
      policy: Cachex.Policy.LRW,
      reclaim: 1.0
    }

    my_cache = TestHelper.create_cache([ max_size: limit ])

    Cachex.execute(my_cache, fn(state) ->
      Enum.each(1..500, fn(x) ->
        Cachex.set(state, x, x)
      end)
    end)

    assert(Cachex.size!(my_cache) == 500)

    Cachex.set(my_cache, 501, 501)

    TestHelper.poll(1000, 0, fn ->
      Cachex.size!(my_cache)
    end)
  end

  test "LRW doesn't check cache size on non-insert operations" do
    limit = %Cachex.Limit{
      limit: 500,
      policy: Cachex.Policy.LRW,
      reclaim: 0.5
    }

    my_cache = TestHelper.create_cache([ max_size: limit ])

    Cachex.execute(my_cache, fn(state) ->
      Enum.each(1..500, fn(x) ->
        Cachex.set(state, x, x)
      end)
    end)

    assert(Cachex.size!(my_cache) == 500)

    :ets.insert(my_cache, { 501, Cachex.Util.now(), nil, 501 })

    assert(Cachex.get!(my_cache, 501) == 501)
    assert(Cachex.size!(my_cache) == 501)

    Cachex.set(my_cache, 501, 501)

    TestHelper.poll(1000, 250, fn ->
      Cachex.size!(my_cache)
    end)
  end

  test "LRW correctly broadcasts evictions to cache hooks" do
    limit = %Cachex.Limit{
      limit: 500,
      policy: Cachex.Policy.LRW,
      reclaim: 0.5
    }

    my_cache = TestHelper.create_cache([
      max_size: limit,
      record_stats: true
    ])

    Cachex.execute(my_cache, fn(state) ->
      Enum.each(1..500, fn(x) ->
        Cachex.set(state, x, x)
      end)
    end)

    Cachex.set(my_cache, 501, 501)

    TestHelper.poll(1000, 250, fn ->
      Cachex.size!(my_cache)
    end)

    stats = Cachex.stats!(my_cache)

    assert(stats.evictionCount == 251)
  end

  test "LRW purges expired entries before evicting old entries" do
    limit = %Cachex.Limit{
      limit: 500,
      policy: Cachex.Policy.LRW,
      reclaim: 0.5
    }

    my_cache = TestHelper.create_cache([
      max_size: limit,
      record_stats: true
    ])

    Cachex.execute(my_cache, fn(state) ->
      Enum.each(1..251, fn(x) ->
        Cachex.set(state, x, x, ttl: 1)
      end)
    end)

    Cachex.execute(my_cache, fn(state) ->
      Enum.each(252..500, fn(x) ->
        Cachex.set(state, x, x)
      end)
    end)

    :timer.sleep(5)

    Cachex.set(my_cache, 501, 501)

    TestHelper.poll(1000, 250, fn ->
      Cachex.size!(my_cache)
    end)

    stats = Cachex.stats!(my_cache)

    assert(stats.expiredCount == 251)
  end

end
