defmodule Cachex.Error do
  @moduledoc """
  Module containing all error definitions used in the codebase.

  This module allows users to catch Cachex errors in a separate block
  to other errors/exceptions rather than using stdlib errors:

      iex> try do
      ...>   Cachex.put!(:cache, "key", "value")
      ...> rescue
      ...>   e in Cachex.Error -> e
      ...> end

  All error messages (both shorthand and long form) can be found in this module,
  including the ability to convert from the short form to the long form using the
  `explain/1` function.
  """
  defexception message: "Error during cache action", stack: nil

  # all shorthands
  @known_errors [
    :cross_slot,
    :eisdir,
    :enoent,
    :invalid_command,
    :invalid_expiration,
    :invalid_hook,
    :invalid_limit,
    :invalid_match,
    :invalid_name,
    :invalid_option,
    :invalid_pairs,
    :invalid_router,
    :invalid_warmer,
    :janitor_disabled,
    :no_cache,
    :non_distributed,
    :non_numeric_value,
    :not_started,
    :stats_disabled
  ]

  ##########
  # Macros #
  ##########

  @doc """
  Generates a tagged `:error` Tuple at compile time.

  The provided error key must be contained in the list of known
  identifiers returned be `known/0`, otherwise this call will fail.
  """
  @spec error(shortname :: atom) :: {:error, shortname :: atom}
  defmacro error(key) when key in @known_errors,
    do: quote(do: {:error, unquote(key)})

  ##############
  # Public API #
  ##############

  @doc """
  Converts an error identifier to it's longer form.

  Error identifiers should be atoms and should be contained in the
  list of errors returned by `known/0`. The return type from this
  function will always be a binary.
  """
  @spec explain(shortname :: atom) :: description :: binary
  def explain(:cross_slot),
    do: "Target keys do not live on the same node"

  def explain(:eisdir),
    do: "A directory path was provided when a file was expected"

  def explain(:enoent),
    do: "Unable to access provided file path"

  def explain(:invalid_command),
    do: "Invalid command definition provided"

  def explain(:invalid_expiration),
    do: "Invalid expiration definition provided"

  def explain(:invalid_hook),
    do: "Invalid hook definition provided"

  def explain(:invalid_limit),
    do: "Invalid limit fields provided"

  def explain(:invalid_match),
    do: "Invalid match specification provided"

  def explain(:invalid_name),
    do: "Invalid cache name provided"

  def explain(:invalid_option),
    do: "Invalid option syntax provided"

  def explain(:invalid_pairs),
    do: "Invalid insertion pairs provided"

  def explain(:invalid_router),
    do: "Invalid router definition provided"

  def explain(:invalid_warmer),
    do: "Invalid warmer definition provided"

  def explain(:janitor_disabled),
    do: "Specified janitor process running"

  def explain(:no_cache),
    do: "Specified cache not running"

  def explain(:non_distributed),
    do: "Attempted to use a local function across nodes"

  def explain(:non_numeric_value),
    do: "Attempted arithmetic operations on a non-numeric value"

  def explain(:not_started),
    do: "Cache table not active, have you started the Cachex application?"

  def explain(:stats_disabled),
    do: "Stats are not enabled for the specified cache"

  def explain(error),
    do: error

  @doc """
  Returns the list of known error keys.
  """
  @spec known :: [shortname :: atom]
  def known,
    do: @known_errors
end
