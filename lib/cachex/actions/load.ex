defmodule Cachex.Actions.Load do
  @moduledoc false
  # Command module to allow deserialization of a cache from disk.
  #
  # Loading a cache from disk requires that it was previously dumped using the
  # `dump()` command (it does not support loading from DETS). Most of the heavy
  # lifting inside this command is done via the `Cachex.Disk` module.
  alias Cachex.Disk

  # we need our imports
  import Cachex.Actions
  import Cachex.Spec

  @doc """
  Loads a previously dumped cache from a file.

  If there are any issues reading the file, an error will be returned. Only files
  which were created via `dump` can be loaded, and the load will detect any disk
  compression automatically.

  Loading a backup will merge the file into the provided cache, overwriting any
  clashes. If you wish to empty the cache and then import your backup, you can
  use a transaction and clear the cache before loading the backup.
  """
  defaction load(cache(name: name) = cache, path, options) do
    with { :ok, terms } <- Disk.read(path, options) do
      { :ok, :ets.insert(name, terms) }
    end
  end
end
