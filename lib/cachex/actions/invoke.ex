defmodule Cachex.Actions.Invoke do
  @moduledoc false
  # This module allows invocation of custom cache commands. A cache command must
  # be of the form `{ :return | :modify, fn/1 }` and reside inside the `:commands`
  # key of the Cache struct. Invocations which modify are carried out inside a
  # Transaction context to ensure consistency. Please see the project documentation
  # for more details.

  # we need our imports
  import Cachex.Actions
  import Cachex.Errors
  import Cachex.Spec

  # add some aliases
  alias Cachex.Actions.Get
  alias Cachex.Cache
  alias Cachex.Services.Locksmith
  alias Cachex.Util

  @doc """
  Invokes a custom command on a cache.

  This allows the developer to attach common functions directly to the cache, in
  order to easily share logic around a codebase without having to write a module.

  Invocation passes the value for a given key through to the custom command, and
  takes action based on the type of command being executed and the return value
  of the command.

  There are currently no options accepted here, but it's required as an argument
  in order to future-proof the arity.
  """
  defaction invoke(%Cache{ commands: commands } = cache, key, cmd, options) do
    commands
    |> Map.get(cmd)
    |> do_invoke(cache, key)
  end

  # In the case of a `:return` function, we just pull the value from the cache
  # and pass it off to be transformed before the result is passed back.
  defp do_invoke(command(type: :read, execute: exec), cache, key) do
    { _status_, value } = Get.execute(cache, key, const(:notify_false))
    { :ok, exec.(value) }
  end

  # In the case of `:modify` functions, we initialize a locking context to ensure
  # consistency, before retrieving the value of the key. This value is then passed
  # through to the command and the return value is used to dictate the new value
  # to be written to the cache, as well as the value to return.
  defp do_invoke(command(type: :write, execute: exec), %Cache{ } = cache, key) do
    Locksmith.transaction(cache, [ key ], fn ->
      { status, value } = Get.execute(cache, key, const(:notify_false))
      { return, tempv } = exec.(value)

      tempv == value || Util
        .write_mod(status)
        .execute(cache, key, tempv, const(:notify_false))

      { :ok, return }
    end)
  end

  # Carries out an invocation. If the command retrieved is invalid, we just pass
  # an error back to the caller instead of trying to do anything too clever.
  defp do_invoke(_cmd, _cache, _key),
    do: error(:invalid_command)
end
