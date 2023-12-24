defmodule Cachex.DiskTest do
  use CachexCase

  # This test just ensures that we can correctly write values to disk when using
  # varying levels of compression and that we can read back the exact same value
  # from disk regardless of compression, and with no knowledge of compression.
  test "working with values going to/from disk" do
    # locate the temporary directory
    tmp = System.tmp_dir!()

    # define our base value to serialize
    values = [
      1,
      "two",
      ~c"three",
      :four,
      %{"five" => true}
    ]

    # define a validation function
    validate = fn options ->
      # generate a new path to write to
      path = Path.join(tmp, Helper.gen_rand_bytes(8))

      # write our base value to the file
      result1 = Cachex.Disk.write(values, path, options)

      # verify the result
      assert(result1 == {:ok, true})

      # reload the file from disk
      result2 = Cachex.Disk.read(path)

      # verify the result is what was written
      assert(result2 == {:ok, values})
    end

    # validate various option sets
    validate.(compression: -1)
    validate.(compression: 0)
    validate.(compression: 1)
    validate.(compression: 5)
    validate.(compression: 9)

    # cause some errors by using invalid paths
    result1 = Cachex.Disk.read(tmp)
    result2 = Cachex.Disk.write(1, tmp)

    # verify the calls failed
    assert(result1 == {:error, :unreachable_file})
    assert(result2 == {:error, :unreachable_file})
  end
end
