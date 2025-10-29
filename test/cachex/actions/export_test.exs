defmodule Cachex.Actions.ExportTest do
  use Cachex.Test.Case

  # This test verifies that it's possible to export the entries from a cache.
  test "exporting records from a cache" do
    # create a test cache
    cache = TestUtils.create_cache()

    # fill with some items
    assert Cachex.put(cache, 1, 1) == {:ok, true}
    assert Cachex.put(cache, 2, 2) == {:ok, true}
    assert Cachex.put(cache, 3, 3) == {:ok, true}

    # export the items
    export = Cachex.export(cache)

    # check the exported count
    assert length(export) == 3
  end

  # This test verifies that the distributed router correctly controls
  # the export/2 action in such a way that it can clean both a local
  # node as well as a remote node. We don't have to check functionality
  # of the entire action; just the actual routing of the action to the
  # target node(s) is of interest here.
  @tag distributed: true
  test "exporting records from a cache cluster" do
    # create a new cache cluster for cleaning
    {cache, _nodes, _cluster} = TestUtils.create_cache_cluster(2)

    # we know that 1 & 2 hash to different nodes
    assert Cachex.put(cache, 1, 1) == {:ok, true}
    assert Cachex.put(cache, 2, 2) == {:ok, true}

    # retrieve the keys from both local & remote
    export1 = Cachex.export(cache, local: true)
    export2 = Cachex.export(cache, local: false)

    # local just one, cluster has two
    assert(length(export1) == 1)
    assert(length(export2) == 2)

    # delete the single local key
    assert Cachex.clear(cache, local: true) == 1

    # retrieve the keys again from both local & remote
    export3 = Cachex.export(cache, local: true)
    export4 = Cachex.export(cache, local: false)

    # now local has no keys
    assert(length(export3) == 0)
    assert(length(export4) == 1)

    # delete the remaining key inside the cluster
    assert Cachex.clear(cache, local: false) == 1

    # retrieve the keys again from both local & remote
    export5 = Cachex.keys(cache, local: true)
    export6 = Cachex.keys(cache, local: false)

    # now both don't have any keys
    assert(length(export5) == 0)
    assert(length(export6) == 0)
  end
end
