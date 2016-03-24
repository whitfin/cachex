defmodule CachexTest.Janitor do
  use PowerAssert

  test "janitor purges expired keys every second by default" do
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
    assert(size_result == { :ok, 0 })
  end

  test "janitor purges expired keys with custom schedule" do
    cache = TestHelper.create_cache([default_ttl: :timer.seconds(1), ttl_interval: :timer.seconds(3)])

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

    :timer.sleep(:timer.seconds(2))

    count_result = Cachex.count(cache)
    assert(count_result == { :ok, 0 })

    size_result = Cachex.size(cache)
    assert(size_result == { :ok, 0 })
  end

end
