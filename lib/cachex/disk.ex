defmodule Cachex.Disk do
  @moduledoc """
  This module contains interaction with disk for serializing terms directly to
  a given file path. This is mainly used for backing up a cache to disk in order
  to be able to export a cache to another instance. Writes can have a compression
  attached and will add basic compression by default.
  """

  # we need constants for errors
  use Cachex.Constants

  # add a Util alias
  alias Cachex.Util

  @doc """
  Reads a file back into an Erlang term.

  If there's an error reading the file, or the file is invalid ETF, an error will
  be returned. Otherwise an :ok Tuple containing the terms will be returned.

  As we can't be certain what we're reading from the file, we make sure to load
  it safely to avoid malicious content (although the chance of that is slim).
  """
  def read(path, options \\ []) when is_binary(path) and is_list(options) do
    path
    |> File.read!
    |> :erlang.binary_to_term([ :safe ])
    |> Util.wrap(:ok)
  rescue
    _ -> @error_unreachable_file
  end

  @doc """
  Writes a set of Erlang terms to a location on disk.

  We allow the user to pass a `:compression` option in order to reduce the output,
  but by default we'll compress using level 1 compression. If the `:compression`
  is set to `0` then compression will be disabled, but be aware storage will
  increase dramatically.
  """
  def write(val, path, options \\ []) when is_binary(path) and is_list(options) do
    binopt =
      options
      |> Util.opt_transform(:compression, &fetch_compress_opt/1)
      |> Keyword.put(:minor_version, 1)

    insert = :erlang.term_to_binary(val, binopt)

    case File.write(path, insert) do
       :ok -> { :ok, true }
      _err -> @error_unreachable_file
    end
  end

  # Used to fetch a compression flag, but only if it's a valid integer between
  # 1 and 9, otherwise we don't compress the output (for fastest performance).
  defp fetch_compress_opt(val) when is_integer(val) and val > -1 and val < 10,
    do: [ compressed: val ]
  defp fetch_compress_opt(_val),
    do: [ compressed: 1 ]


end
