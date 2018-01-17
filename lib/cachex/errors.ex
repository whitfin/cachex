defmodule Cachex.Errors do
  @moduledoc """
  Module containing all error definitions used in the codebase.

  All error messages (both shorthand and long form) can be found in this module,
  including the ability to convert from the short form to the long form using the
  `long_form/1` function.

  This module is provided to allow functions to return short errors, using the
  easy syntax of `error(:short_name)` to generate a tuple of `{ :error, :short_name }`
  but also to allow them to be converted to a readable form as needed, rather
  than bloating blocks with potentially large error messages.
  """
  @known_errors [
    :invalid_command,  :invalid_expiration, :invalid_fallback,
    :invalid_hook,     :invalid_limit,      :invalid_match,
    :invalid_name,     :invalid_option,     :invalid_pairs,
    :janitor_disabled, :no_cache,           :non_numeric_value,
    :not_started,      :stats_disabled,     :unreachable_file
  ]

  ##########
  # Macros #
  ##########

  @doc """
  Generates a tagged `:error` Tuple at compile time.

  The provided error key must be contained in the list of known
  identifiers returned be `known/0`, otherwise this call will fail.
  """
  @spec error(atom) :: { :error, atom }
  defmacro error(key) when key in @known_errors,
    do: quote(do: { :error, unquote(key) })

  ##############
  # Public API #
  ##############

  @doc """
  Returns the list of known error keys.
  """
  @spec known :: [ atom ]
  def known,
    do: @known_errors

  @doc """
  Converts an error identifier to it's longer form.

  Error identifiers should be atoms and should be contained in the
  list of errors returned by `known/0`. The return type from this
  function will always be a binary.

  If an invalid error identifer is provided, there will simply be an error due
  to no matching function head (and this is intended).
  """
  @spec long_form(atom) :: binary
  def long_form(:invalid_command),
    do: "Invalid command definition provided"
  def long_form(:invalid_expiration),
    do: "Invalid expiration definition provided"
  def long_form(:invalid_fallback),
    do: "Invalid fallback function provided"
  def long_form(:invalid_hook),
    do: "Invalid hook definition provided"
  def long_form(:invalid_limit),
    do: "Invalid limit fields provided"
  def long_form(:invalid_match),
    do: "Invalid match specification provided"
  def long_form(:invalid_name),
    do: "Invalid cache name provided"
  def long_form(:invalid_option),
    do: "Invalid option syntax provided"
  def long_form(:invalid_pairs),
    do: "Invalid insertion pairs provided"
  def long_form(:janitor_disabled),
    do: "Specified janitor process running"
  def long_form(:no_cache),
    do: "Specified cache not running"
  def long_form(:non_numeric_value),
    do: "Attempted arithmetic operations on a non-numeric value"
  def long_form(:not_started),
    do: "Cache table not active, have you started the Cachex application?"
  def long_form(:stats_disabled),
    do: "Stats are not enabled for the specified cache"
  def long_form(:unreachable_file),
    do: "Unable to access provided file path"
end
