defmodule Cachex.Actions.StreamTest do
  use Cachex.Test.Case

  # This test ensures that a default cache stream will stream cache entries
  # back in record form back to the calling process. This test just makes sure
  # that the Stream correctly forms these Tuples using the default structure.
  test "streaming cache entries" do
    # create a test cache
    cache = TestUtils.create_cache()

    # add some keys to the cache
    assert Cachex.put(cache, "key1", "value1")
    assert Cachex.put(cache, "key2", "value2")
    assert Cachex.put(cache, "key3", "value3")

    # create and consume a cache stream
    result =
      cache
      |> Cachex.stream()
      |> Enum.sort()

    # verify the results are the ordered entries
    assert result == [
             Cachex.inspect(cache, {:entry, "key1"}),
             Cachex.inspect(cache, {:entry, "key2"}),
             Cachex.inspect(cache, {:entry, "key3"})
           ]
  end

  # This test covers the use case of custom match patterns, by testing various
  # pattern combinations. We stream custom record formats, as well as a single
  # field in order to test this properly.
  test "streaming custom patterns" do
    # create a test cache
    cache = TestUtils.create_cache()

    # add some keys to the cache
    assert Cachex.put(cache, "key1", "value1")
    assert Cachex.put(cache, "key2", "value2")
    assert Cachex.put(cache, "key3", "value3")

    # create our query filter
    filter = Cachex.Query.unexpired()

    # create two test queries
    query1 = Cachex.Query.build(where: filter, output: {:key, :value})
    query2 = Cachex.Query.build(where: filter, output: :key)

    # create cache streams
    stream1 = Cachex.stream(cache, query1)
    stream2 = Cachex.stream(cache, query2)

    # verify the first results
    assert Enum.sort(stream1) == [
             {"key1", "value1"},
             {"key2", "value2"},
             {"key3", "value3"}
           ]

    # verify the second results
    assert Enum.sort(stream2) == ["key1", "key2", "key3"]
  end

  # If an invalid match spec is provided in the of option, an error is returned.
  # We just ensure that this breaks accordingly and returns an invalid match error.
  test "streaming invalid patterns" do
    # create a test cache
    cache = TestUtils.create_cache()

    # create cache stream, verify the stream fails
    assert Cachex.stream(cache, {:invalid}) == {:error, :invalid_match}
  end

  # This test verifies that this action is correctly disabled in a cluster,
  # as it's currently unsupported - so just check for disabled flags.
  @tag distributed: true
  test "streaming is disabled in a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we shouldn't be able to stream a cache on multiple nodes
    assert Cachex.stream(cache) == {:error, :non_distributed}
  end

  # We can force local: true to get a stream against the local node
  @tag distributed: true
  test "streaming is enabled in a cache cluster with local: true" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # build a generic query to use later
    query = Cachex.Query.build()

    # create a cache stream with the local flag, we should be able to stream
    assert Cachex.stream(cache, query, local: true) != {:error, :non_distributed}
  end
end
