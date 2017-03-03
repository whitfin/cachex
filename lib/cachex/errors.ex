defmodule Cachex.Errors do
  @moduledoc false
  # This module simply contains the necessary translations from the built in error
  # message to their long (non-atom) form. Used to allow functions to return short
  # errors such as `{ :error, :short_name }` and have them converted after the
  # fact, rather than bloating actions with potentially large error messages.

  @doc """
  Converts an error identifier to it's longer form.

  Error identifiers should be atoms and consist of those errors inside the module
  `Cachex.Constants`. The return type from this function will always be a binary.

  If an invalid error identifer is provided, there will simply be an error due
  to no matching function head (and this is intended).
  """
  def long_form(:invalid_command),
    do: "Invalid command definition provided"
  def long_form(:invalid_hook),
    do: "Invalid hook definition provided"
  def long_form(:invalid_match),
    do: "Invalid match specification provided"
  def long_form(:invalid_name),
    do: "Invalid cache name provided"
  def long_form(:invalid_option),
    do: "Invalid option syntax provided"
  def long_form(:janitor_disabled),
    do: "Specified janitor process running"
  def long_form(:no_cache),
    do: "Specified cache not running"
  def long_form(:non_numeric_value),
    do: "Attempted arithmetic operations on a non-numeric value"
  def long_form(:not_started),
    do: "State table not active, have you started the Cachex application?"
  def long_form(:stats_disabled),
    do: "Stats are not enabled for the specified cache"
  def long_form(:unreachable_file),
    do: "Unable to access provided file path"

end
