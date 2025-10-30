defmodule Cachex.Limit.AccessedTest do
  use Cachex.Test.Case

  # Basic coverage of the access hook to ensure that modification
  # times are refreshed on a read call for a key. More specific
  # tests will be added as new test cases and issues arise.
  test "updating modification times on read access" do
    # create a test cache using the LRW access hook to refresh modification
    cache = TestUtils.create_cache(hooks: [hook(module: Cachex.Limit.Accessed)])

    # create a new key to check against
    {:ok, true} = Cachex.put(cache, "key", 1)

    # fetch the raw modification time of the cache entry
    entry(modified: modified1) = Cachex.inspect!(cache, {:entry, "key"})

    # wait a while...
    :timer.sleep(50)

    # fetch back the key again
    assert Cachex.get(cache, "key") == 1

    # the modification time should update...
    TestUtils.poll(250, true, fn ->
      cache
      |> Cachex.inspect!({:entry, "key"})
      |> entry(:modified) != modified1
    end)
  end
end
