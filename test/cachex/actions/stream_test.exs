defmodule Cachex.Actions.StreamTest do
  use CachexCase

  # This test ensures that a default cache stream will stream keys and values
  # back in Tuple pairs back to the calling process. This test just makes sure
  # that the Stream correctly forms these Tuples using the default structure.
  test "streaming keys and values" do
    # create a test cache
    cache = Helper.create_cache()

    # add some keys to the cache
    { :ok, true } = Cachex.set(cache, "key1", "value1")
    { :ok, true } = Cachex.set(cache, "key2", "value2")
    { :ok, true } = Cachex.set(cache, "key3", "value3")

    # create a cache stream
    { :ok, stream } = Cachex.stream(cache)

    # consume the stream
    result = Enum.sort(stream)

    # verify the results
    assert(result == [
      { "key1", "value1" },
      { "key2", "value2" },
      { "key3", "value3" }
    ])
  end

  # This test covers the use case of custom match patterns, by testing various
  # pattern combinations. We stream custom record formats, as well as a single
  # field in order to test this properly.
  test "streaming custom patterns" do
    # create a test cache
    cache = Helper.create_cache()

    # add some keys to the cache
    { :ok, true } = Cachex.set(cache, "key1", "value1")
    { :ok, true } = Cachex.set(cache, "key2", "value2")
    { :ok, true } = Cachex.set(cache, "key3", "value3")

    # create cache streams
    { :ok, stream1 } = Cachex.stream(cache, [ of: { { :key, :value, :key, :ttl } } ])
    { :ok, stream2 } = Cachex.stream(cache, [ of: :key ])

    # consume the streams
    result1 = Enum.sort(stream1)
    result2 = Enum.sort(stream2)

    # verify the first results
    assert(result1 == [
      { "key1", "value1", "key1", nil },
      { "key2", "value2", "key2", nil },
      { "key3", "value3", "key3", nil }
    ])

    # verify the second results
    assert(result2 == [ "key1", "key2", "key3" ])
  end

  # If an invalid match spec is provided in the of option, an error is returned.
  # We just ensure that this breaks accordingly and returns an invalid match error.
  test "streaming invalid patterns" do
    # create a test cache
    cache = Helper.create_cache()

    # create cache stream
    result  = Cachex.stream(cache, [ of: { :invalid } ])

    # verify the stream fails
    assert(result == { :error, :invalid_match })
  end
end
