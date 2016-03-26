defmodule CachexTest.Janitor do
  use PowerAssert

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
    cache = TestHelper.create_cache([default_ttl: 100, ttl_interval: 100])

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

    :timer.sleep(200)

    count_result = Cachex.count(cache)
    assert(count_result == { :ok, 0 })

    size_result = Cachex.size(cache)
    assert(size_result == { :ok, 0 })
  end

end
