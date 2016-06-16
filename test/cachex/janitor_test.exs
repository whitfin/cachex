defmodule Cachex.JanitorTest do
  use PowerAssert, async: false

  test "janitor purges expired keys every 3 seconds by default" do
    cache = TestHelper.create_cache([default_ttl: :timer.seconds(1)])

    Enum.each(1..15, fn(x) ->
      key = "my_key" <> to_string(x)

      set_result = Cachex.set(cache, key, "my_value")
      assert(set_result == { :ok, true })

      get_result = Cachex.get(cache, key)
      assert(get_result == { :ok, "my_value" })
    end)

    count_result = Cachex.count(cache)
    assert(count_result == { :ok, 15 })

    size_result = Cachex.size(cache)
    assert(size_result == { :ok, 15 })

    :timer.sleep(:timer.seconds(2))

    count_result = Cachex.count(cache)
    assert(count_result == { :ok, 0 })

    size_result = Cachex.size(cache)
    assert(size_result == { :ok, 15 })

    :timer.sleep(:timer.seconds(1))

    count_result = Cachex.count(cache)
    assert(count_result == { :ok, 0 })

    size_result = Cachex.size(cache)
    assert(size_result == { :ok, 0 })
  end

  test "janitor purges expired keys with custom schedule" do
    cache = TestHelper.create_cache([default_ttl: 25, ttl_interval: 25])

    Enum.each(1..15, fn(x) ->
      key = "my_key" <> to_string(x)

      set_result = Cachex.set(cache, key, "my_value")
      assert(set_result == { :ok, true })

      get_result = Cachex.get(cache, key)
      assert(get_result == { :ok, "my_value" })
    end)

    count_result = Cachex.count(cache)
    assert(count_result == { :ok, 15 })

    size_result = Cachex.size(cache)
    assert(size_result == { :ok, 15 })

    :timer.sleep(50)

    count_result = Cachex.count(cache)
    assert(count_result == { :ok, 0 })

    size_result = Cachex.size(cache)
    assert(size_result == { :ok, 0 })
  end

  test "janitor correctly notifies a stats hook", _state do
    cache = TestHelper.create_cache([default_ttl: 1, ttl_interval: 1, record_stats: true])

    :timer.sleep(3)

    { stats_status, stats_result } = Cachex.stats(cache, for: [ :purge ])

    assert(stats_status == :ok)
    assert(stats_result[:purge] == %{ })

    set_result = Cachex.set(cache, "my_key", "my_value")
    assert(set_result == { :ok, true })

    :timer.sleep(5)

    { stats_status, stats_result } = Cachex.stats(cache, for: [ :purge ])

    assert(stats_status == :ok)
    assert(stats_result[:purge] == %{ total: 1 })
  end

end
