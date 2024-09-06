defmodule Cachex.Actions.StreamTest do
  use Cachex.Test.Case

  # This test ensures that a default cache stream will stream cache entries
  # back in record form back to the calling process. This test just makes sure
  # that the Stream correctly forms these Tuples using the default structure.
  test "streaming cache entries" do
    # create a test cache
    cache = TestUtils.create_cache()

    # add some keys to the cache
    {:ok, true} = Cachex.put(cache, "key1", "value1")
    {:ok, true} = Cachex.put(cache, "key2", "value2")
    {:ok, true} = Cachex.put(cache, "key3", "value3")

    # grab the raw versions of each record
    {:ok, entry1} = Cachex.inspect(cache, {:entry, "key1"})
    {:ok, entry2} = Cachex.inspect(cache, {:entry, "key2"})
    {:ok, entry3} = Cachex.inspect(cache, {:entry, "key3"})

    # create a cache stream
    {:ok, stream} = Cachex.stream(cache)

    # consume the stream
    result = Enum.sort(stream)

    # verify the results are the ordered entries
    assert(result == [entry1, entry2, entry3])
  end

  # This test covers the use case of custom match patterns, by testing various
  # pattern combinations. We stream custom record formats, as well as a single
  # field in order to test this properly.
  test "streaming custom patterns" do
    # create a test cache
    cache = TestUtils.create_cache()

    # add some keys to the cache
    {:ok, true} = Cachex.put(cache, "key1", "value1")
    {:ok, true} = Cachex.put(cache, "key2", "value2")
    {:ok, true} = Cachex.put(cache, "key3", "value3")

    # create two test queries
    query1 = Cachex.Query.create(expired: false, output: {:key, :value})
    query2 = Cachex.Query.create(expired: false, output: :key)

    # create cache streams
    {:ok, stream1} = Cachex.stream(cache, query1)
    {:ok, stream2} = Cachex.stream(cache, query2)

    # consume the streams
    result1 = Enum.sort(stream1)
    result2 = Enum.sort(stream2)

    # verify the first results
    assert(
      result1 == [
        {"key1", "value1"},
        {"key2", "value2"},
        {"key3", "value3"}
      ]
    )

    # verify the second results
    assert(result2 == ["key1", "key2", "key3"])
  end

  # If an invalid match spec is provided in the of option, an error is returned.
  # We just ensure that this breaks accordingly and returns an invalid match error.
  test "streaming invalid patterns" do
    # create a test cache
    cache = TestUtils.create_cache()

    # create cache stream
    result = Cachex.stream(cache, {:invalid})

    # verify the stream fails
    assert(result == {:error, :invalid_match})
  end

  # This test verifies that this action is correctly disabled in a cluster,
  # as it's currently unsupported - so just check for disabled flags.
  @tag distributed: true
  test "streaming is disabled in a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we shouldn't be able to stream a cache on multiple nodes
    assert(Cachex.stream(cache) == {:error, :non_distributed})
  end
end
