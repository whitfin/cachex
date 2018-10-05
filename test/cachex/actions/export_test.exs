defmodule Cachex.Actions.ExportTest do
  use CachexCase

  # This test verifies that it's possible to export the entries from a cache.
  # As it stands, this is a barebones test to ensure the length of the export
  # as it's covered more heavily by the test cases based on `dump/3`.
  test "exporting the records from inside the cache" do
    # create a test cache
    cache = Helper.create_cache()

    # fill with some items
    { :ok, true } = Cachex.put(cache, 1, 1)
    { :ok, true } = Cachex.put(cache, 2, 2)
    { :ok, true } = Cachex.put(cache, 3, 3)

    # export the items
    { :ok, export } = Cachex.export(cache)

    # check the exported count
    assert length(export) == 3
  end
end
