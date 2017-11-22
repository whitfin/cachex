defmodule Cachex.Actions.Dump do
  @moduledoc false
  # This module controls the implementation for the `dump` command, which writes
  # out a given cache directly to disk at the provided file location. This can
  # then be imported using the `load` command to allow moving of caching between
  # nodes and machines.

  # we need our imports
  import Cachex.Actions

  # add some aliases
  alias Cachex.Cache
  alias Cachex.Disk

  @doc """
  Dumps a cache to disk at the given location.

  This call will return an error if anything goes wrong with writing the file;
  it is up to the caller to ensure the file is writeable using the default `File`
  interfaces.

  By default, files are written to disk with level 1 compression due to performance
  implications but the `:compression` option can be passed as an integer between
  1 and 9 (inclusive) to specify a compression level.

  Passing a 0 compressed flag will disable compression. This is way faster than
  the default compression, but the file size will increase dramatically.
  """
  defaction dump(%Cache{ name: name } = cache, path, options) do
    name
    |> :ets.tab2list
    |> Disk.write(path, options)
  end
end
