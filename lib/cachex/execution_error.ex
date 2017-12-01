defmodule Cachex.ExecutionError do
  @moduledoc """
  Minor error implementation for all Cachex-specific errors.

  This module allows users caton catch Cachex errors in a separate
  block to other errors/exceptions rather than using stdlib errors.

      iex> try do
      ...>   Cachex.set!(:cache, "key", "value")
      ...> rescue
      ...>   e in Cachex.ExecutionError -> e
      ...> end

  The default error message should always be overridden with a long
  error formas displayed inside `Cachex.Errors`.
  """
  defexception message: "Error during action execution"
end
