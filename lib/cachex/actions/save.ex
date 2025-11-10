defmodule Cachex.Actions.Save do
  @moduledoc false
  # Command module to allow serialization of a cache to disk.
  #
  # Rather than using DETS to back up the internal ETS table, this module will
  # serialize the entire table using a `Cachex.stream/3`.
  #
  # Backups can be imported again using the `Cachex.restore/3` command, and
  # should be ble to be transferred between processes and physical nodes.
  alias Cachex.Options
  alias Cachex.Query
  alias Cachex.Router.Local

  # import our macros
  import Cachex.Error
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Dumps a cache to disk at the given location.

  This call will return an error if anything goes wrong with writing the file;
  it is up to the caller to ensure the file is writeable using the default `File`
  interfaces.
  """
  def execute(cache(router: router(module: router)) = cache, path, options) do
    file = File.open!(path, [:write, :compressed])
    buffer = Options.get(options, :buffer, &is_positive_integer/1, 25)

    options
    |> Keyword.get(:local)
    |> init_stream(router, cache, buffer)
    |> Stream.chunk_every(buffer)
    |> Stream.map(&handle_batch/1)
    |> Enum.each(&IO.binwrite(file, &1))

    File.close(file)
  rescue
    File.Error -> error(:unreachable_file)
  end

  ###############
  # Private API #
  ###############

  # Use a local stream to lazily walk through records on a local cache.
  defp init_stream(local, router, cache, buffer) when local or router == Local do
    options =
      :local
      |> const()
      |> Enum.concat(const(:notify_false))
      |> Enum.concat(buffer: buffer)

    Cachex.stream(cache, Query.build(), options)
  end

  # Generate an export of all nodes in a distributed cluster via `Cachex.export/2`
  defp init_stream(_local, _router, cache, _buffer),
    do: Cachex.export(cache, const(:notify_false))

  # Handle a batch of records and generate a binary of each.
  defp handle_batch(buffer) do
    Enum.reduce(buffer, <<>>, fn tuple, acc ->
      binary = :erlang.term_to_binary(tuple)
      size = byte_size(binary)
      acc <> <<size::24-unsigned>> <> binary
    end)
  end
end
