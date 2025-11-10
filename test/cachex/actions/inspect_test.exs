defmodule Cachex.Actions.InspectTest do
  use Cachex.Test.Case

  # This test ensures that we can correctly inspect various things related to
  # expired keys inside the cache. We need to make sure that the check both the
  # count of expired keys, as well as retrieving a list of expired keys.
  test "inspecting expired keys" do
    # create a test cache
    cache = TestUtils.create_cache()

    # set several values in the cache
    for x <- 1..3 do
      assert Cachex.put(cache, "key#{x}", "value#{x}", expire: 1) == :ok
    end

    # make sure they expire
    :timer.sleep(2)

    # the first should contain the count of expired keys
    assert Cachex.inspect(cache, {:expired, :count}) == 3

    # break down the expired key set
    expired =
      cache
      |> Cachex.inspect({:expired, :keys})
      |> Enum.sort()

    # verify all expired keys
    assert expired == ["key1", "key2", "key3"]
  end

  # This test ensures that we can see the results of the last time a Janitor
  # process ran. This inspection will simply call the Janitor process to retrieve
  # the last metadata - we don't have to validate what exactly is inside here
  # beyond the fact that it returns successfully. We should also test that an
  # error is returned if there is no Janitor process started for the cache.
  test "inspecting janitor metadata" do
    # create a cache with no janitor and one with
    cache1 = TestUtils.create_cache(expiration: expiration(interval: nil))
    cache2 = TestUtils.create_cache(expiration: expiration(interval: 1))

    # let the janitor run
    :timer.sleep(2)

    # the first cache should have an error because janitor has been disabled
    assert Cachex.inspect(cache1, {:janitor, :last}) == {:error, :janitor_disabled}

    # fetch the second cache to verify the metadata
    result = Cachex.inspect(cache2, {:janitor, :last})

    # check the metadata matches the patterns
    assert is_integer(result.count)
    assert is_integer(result.duration)
    assert is_integer(result.started)
  end

  # This test verifies that we can return stats about the memory being used by a
  # cache. This inspection can be coupled with a flag which returns the results
  # as either a binary or a number of bytes.
  test "inspecting cache memory" do
    # create a test cache
    cache = TestUtils.create_cache()

    # retrieve the memory usage
    result1 = Cachex.inspect(cache, {:memory, :bytes})
    result2 = Cachex.inspect(cache, {:memory, :binary})
    result3 = Cachex.inspect(cache, {:memory, :words})

    # the first result should be a number of bytes
    assert is_positive_integer(result1)

    # the second result should be a human readable representation
    assert result2 =~ ~r/\d+.\d{2} KiB/

    # fetch the system word size
    wsize = :erlang.system_info(:wordsize)

    # verify the words in the byte result
    words = div(result1, wsize)

    # the third should be a number of words
    assert result3 == words
  end

  # This test verifies that we can retrieve a raw cache record without doing any
  # extra work such as checking TTLs. We check that a missing record returns a
  # nil, and that an existing record returns the record.
  test "inspecting cache records" do
    # create a test cache
    cache = TestUtils.create_cache()

    # get the current time
    ctime = now()

    # set a cache record
    assert Cachex.put(cache, 1, "one", expire: 1000)

    # break down the first record
    entry(key: key, modified: mod, expiration: exp, value: value) =
      Cachex.inspect(cache, {:entry, 1})

    # verify the first record
    assert key == 1
    assert_in_delta mod, ctime, 2
    assert exp == 1000
    assert value == "one"

    # the second should be nil
    assert Cachex.inspect(cache, {:entry, 2}) == nil
  end

  # This test simply ensures that inspecting the cache state will return you the
  # cache state. This should always match the latest copy of the state, rather
  # than using the state passed in. This is the only thing to verify.
  test "inspecting cache state" do
    # create a test cache
    cache = TestUtils.create_cache()

    # retrieve the cache state
    state1 = Services.Overseer.lookup(cache)

    # update the state to have a different setting
    state2 =
      Services.Overseer.update(cache, fn state ->
        cache(state, transactions: true)
      end)

    # ensure the states don't match
    assert Cachex.inspect(state1, :cache) != state1

    # the result should be using the latest state
    assert Cachex.inspect(state1, :cache) == state2
  end

  # This test just verifies that we return an invalid option error when the value
  # is unrecognised. There's nothing else to validate beyond the error.
  test "inspecting invalid options" do
    # create a test cache
    cache = TestUtils.create_cache()

    # check the result is an error
    assert Cachex.inspect(cache, :invalid) == {:error, :invalid_option}
  end

  # This test verifies that the inspector always runs locally. We
  # just write a key to both nodes in a cluster, and only one inspect
  # call should find it - due to being only routed to the local node.
  @tag distributed: true
  test "inspections always run on the local node" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    assert Cachex.put(cache, 1, 1)
    assert Cachex.put(cache, 2, 2)

    # lookup both entries on the local node
    entry1 = Cachex.inspect(cache, {:entry, 1})
    entry2 = Cachex.inspect(cache, {:entry, 2})

    # only one of them should be correctly found
    assert (entry1 == nil && entry2 != nil) || (entry2 == nil && entry1 != nil)
  end
end
