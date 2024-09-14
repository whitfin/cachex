defmodule Cachex.Actions.Save do
  @moduledoc false
  # Command module to allow serialization of a cache to disk.
  #
  # Rather than using DETS to back up the internal ETS table, this module will
  # serialize the entire table using a `Cachex.stream/3`.
  #
  # Backups can be imported again using the `Cachex.restore/3` command, and
  # should be ble to be transferred between processes and physical nodes.
  alias Cachex.Actions.Stream, as: CachexStream
  alias Cachex.Options
  alias Cachex.Query
  alias Cachex.Router.Local

  # import our macros
  import Cachex.Errors
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
    batch = Options.get(options, :batch_size, &is_positive_integer/1, 25)
    file = File.open!(path, [:write, :compressed])

    {:ok, stream} =
      options
      |> Keyword.get(:local)
      |> init_stream(router, cache, batch)

    stream
    |> Stream.chunk_every(batch)
    |> Stream.map(&handle_batch/1)
    |> Enum.each(&IO.binwrite(file, &1))

    with :ok <- File.close(file) do
      {:ok, true}
    end
  rescue
    File.Error -> error(:unreachable_file)
  end

  # Use a local stream to lazily walk through records on a local cache.
  defp init_stream(local, router, cache, batch) when local or router == Local,
    do: CachexStream.execute(cache, Query.build(), batch_size: batch)

  # Generate an export of all nodes in a distributed cluster via `Cachex.export/2`
  defp init_stream(_local, _router, cache, _batch),
    do: Cachex.export(cache, const(:notify_false))

  # Handle a batch of records and generate a binary of each.
  defp handle_batch(batch) do
    Enum.reduce(batch, <<>>, fn tuple, acc ->
      binary = :erlang.term_to_binary(tuple)
      size = byte_size(binary)
      acc <> <<size::24-unsigned>> <> binary
    end)
  end
end
