defmodule Cachex.ExecutionError do
  @moduledoc false
  # Minor error implmentation so that users can catch Cachex-specific errors in
  # a separate block to other errors.

  @doc false
  defexception message: "Error during action execution"
end
