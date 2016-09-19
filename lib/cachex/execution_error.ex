defmodule Cachex.ExecutionError do
  @moduledoc false
  # Minor error implmentation so that users can catch Cachex-specific errors in
  # a separate block to other errors/exceptions.
  #
  # iex> try do
  # ...>   Cachex.set!(:cache, "key", "value")
  # ...> rescue
  # ...>   e in Cachex.ExecutionError -> e
  # ...> end
  #
  # The default error message should always be overridden with a long error form
  # as displayed inside `Cachex.Errors`.

  @doc false
  defexception message: "Error during action execution"
end
