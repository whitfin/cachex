defmodule CachexTest.Stream do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "stream requires an existing cache name", _state do
    assert(Cachex.stream("test") == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "stream with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.stream!(state_result) |> Enum.to_list == [])
  end

  test "stream returns a stream of keys and values", state do
    Enum.each(1..3, fn(x) ->
      set_result = Cachex.set(state.cache, "key#{x}", "value#{x}")
      assert(set_result == { :ok, true })
    end)

    { status, stream } = Cachex.stream(state.cache)

    assert(status == :ok)

    sorted_stream =
      stream
      |> Enum.sort
      |> Enum.to_list

      assert(sorted_stream == [
        {"key1", "value1"},
        {"key2", "value2"},
        {"key3", "value3"}
      ])
  end

  test "stream returns a stream of only keys", state do
    Enum.each(1..3, fn(x) ->
      set_result = Cachex.set(state.cache, "key#{x}", "value#{x}")
      assert(set_result == { :ok, true })
    end)

    { status, stream } = Cachex.stream(state.cache, only: :keys)

    assert(status == :ok)

    sorted_stream =
      stream
      |> Enum.sort
      |> Enum.to_list

    assert(sorted_stream == ["key1", "key2", "key3"])
  end

  test "stream returns a stream of only values", state do
    Enum.each(1..3, fn(x) ->
      set_result = Cachex.set(state.cache, "key#{x}", "value#{x}")
      assert(set_result == { :ok, true })
    end)

    { status, stream } = Cachex.stream(state.cache, only: :values)

    assert(status == :ok)

    sorted_stream =
      stream
      |> Enum.sort
      |> Enum.to_list

    assert(sorted_stream == ["value1", "value2", "value3"])
  end

  test "stream returns a moving view of a cache", state do
    Enum.each(1..3, fn(x) ->
      set_result = Cachex.set(state.cache, "key#{x}", "value#{x}")
      assert(set_result == { :ok, true })
    end)

    { status, stream } = Cachex.stream(state.cache)

    assert(status == :ok)

    set_result = Cachex.set(state.cache, "key4", "value4")
    assert(set_result == { :ok, true })

    sorted_stream =
      stream
      |> Enum.sort
      |> Enum.to_list

    assert(sorted_stream == [
      {"key1", "value1"},
      {"key2", "value2"},
      {"key3", "value3"},
      {"key4", "value4"}
    ])
  end

end
