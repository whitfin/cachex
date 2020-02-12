defmodule Cachex.Disk do
  @moduledoc """
  Module dedicated to basic filesystem iteractions.

  This module contains the required interactions with a filesystem for serializing
  terms directly to a given file path. This is mainly used by the backup/restore
  feature of a cache in order to provide easy export functionality.

  The behaviours in here are general enough that they can be used for various use
  cases rather than just cache serialization, and compression can also be controlled.
  """
  alias Cachex.Options
  import Cachex.Errors
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Reads a file from a filesystem using the Erlang Term Format.

  If there's an error reading the file, or the file is invalid ETF, an error will
  be returned. Otherwise a Tuple containing the terms will be returned.

  As we can't be certain what we're reading from the file, we make sure to load
  it safely to avoid malicious content (although the chance of that is slim).
  """
  @spec read(binary, Keyword.t) :: { :ok, any } | { :error, atom }
  def read(path, options \\ []) when is_binary(path) and is_list(options) do
    path
    |> File.read!
    |> :erlang.binary_to_term([ :safe ])
    |> wrap(:ok)
  rescue
    _ -> error(:unreachable_file)
  end

  @doc """
  Writes a value to a filesystem using the Erlang Term Format.

  The compression can be controlled using the `:compression` option in order to
  reduce the size of the output. By default this value will be set to level 1
  compression. If set to 0, compression will be disabled but be aware storage
  will increase dramatically.
  """
  @spec write(any, binary, Keyword.t) :: { :ok, true } | { :error, atom }
  def write(value, path, options \\ []) when is_binary(path) and is_list(options) do
    compression = Options.get(options, :compression, fn(val) ->
      is_integer(val) and val > -1 and val < 10
    end, 1)

    insert = :erlang.term_to_binary(value, [
      compressed: compression,
      minor_version: 1
    ])

    case File.write(path, insert) do
       :ok -> { :ok, true }
      _err -> error(:unreachable_file)
    end
  end
end
