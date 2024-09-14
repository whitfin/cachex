defmodule Cachex.Actions.Restore do
  @moduledoc false
  # Command module to allow deserialization of a cache from disk.
  #
  # Loading a cache from disk requires that it was previously saved using the
  # `Cachex.save/3` command (it does not support loading from DETS).
  alias Cachex.Actions.Import
  alias Cachex.Options

  # we need our imports
  import Cachex.Errors
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Loads a previously saved cache from a file.

  If there are any issues reading the file, an error will be returned. Only files
  which were created via `Cachex.save/3` can be loaded, and the load will detect
  any disk compression automatically.

  Loading a backup will merge the file into the provided cache, overwriting any
  clashes. If you wish to empty the cache and then import your backup, you can
  use a transaction and clear the cache before loading the backup.
  """
  def execute(cache() = cache, path, options) do
    option =
      case Options.get(options, :trust, &is_boolean/1, true) do
        true -> []
        _any -> [:safe]
      end

    stream =
      Stream.resource(
        fn ->
          File.open!(path, [:read, :compressed])
        end,
        &read_next_term(&1, option),
        &File.close/1
      )

    Import.execute(cache, stream, [])
  rescue
    File.Error -> error(:unreachable_file)
  end

  # Read the next term from a file handle cbased on the TLV flags. Each
  # term should be emitted back to the parent stream for processing.
  defp read_next_term(file, options) do
    case IO.binread(file, 3) do
      :eof ->
        {:halt, file}

      <<size::24-unsigned>> ->
        term =
          file
          |> IO.binread(size)
          |> :erlang.binary_to_term(options)

        {[term], file}
    end
  end
end
