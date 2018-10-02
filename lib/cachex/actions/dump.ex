defmodule Cachex.Actions.Dump do
  @moduledoc false
  # Command module to allow serialization of a cache to disk.
  #
  # Rather than using DETS to back up the internal ETS table, this module will
  # serialize the entire table using the ETF via the `Cachex.Disk` module.
  #
  # Backups can be imported again using the `load()` command, and should be
  # able to be transferred between processes and physical nodes.
  alias Cachex.Disk

  # import our macros
  import Cachex.Spec

  ##############
  # Public API #
  ##############

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
  def execute(cache(name: name), path, options) do
    name
    |> :ets.tab2list
    |> Disk.write(path, options)
  end
end
