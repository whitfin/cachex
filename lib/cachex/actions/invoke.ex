defmodule Cachex.Actions.Invoke do
  @moduledoc false
  # Command module to enable custom command invocation.
  #
  # This module relies on commands attached to a cache at startup, and
  # does not allow for registration afterward.
  #
  # Invocations which require writes to the table are executed inside a
  # transactional context to ensure consistency.
  alias Cachex.Actions
  alias Cachex.Services.Locksmith

  # add our imports
  import Cachex.Errors
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Invokes a custom command on a cache.

  Command invocations allow a developer to attach common functions directly to a
  cache in order to easily share logic around a codebase. Values are passed through
  to a custom command for a given key, and based on the type of command might be
  written back into the cache table.
  """
  def execute(cache(commands: commands) = cache, cmd, key, _options) do
    commands
    |> Map.get(cmd)
    |> invoke(cache, key)
  end

  ###############
  # Private API #
  ###############

  # Executes a read command on the backing cache table.
  #
  # Values read back will be passed directly to the custom command implementation.
  # It should be noted that expirations are taken into account, and nil will be
  # passed through in expired/missing cases.
  defp invoke(command(type: :read, execute: exec), cache, key) do
    {_status_, value} = Cachex.get(cache, key, [])
    {:ok, exec.(value)}
  end

  # Executes a write command on the backing cache table.
  #
  # This will initialize a transactional context to ensure that modifications are
  # kept in sync with other actions happening at the same time. The return format
  # is enforced per the documentation and will crash out if something unexpected
  # is returned (i.e. a non-Tuple, or a Tuple with invalid size).
  defp invoke(command(type: :write, execute: exec), cache() = cache, key) do
    Locksmith.transaction(cache, [key], fn ->
      {_label, value} = Cachex.get(cache, key, [])
      {return, tempv} = exec.(value)

      tempv == value ||
        apply(
          Cachex,
          Actions.write_op(value),
          [cache, key, tempv, []]
        )

      {:ok, return}
    end)
  end

  # Returns an error due to a missing command.
  defp invoke(_invalid, _cache, _key),
    do: error(:invalid_command)
end
