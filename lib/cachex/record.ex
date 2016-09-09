defmodule Cachex.Record do
  @moduledoc false
  # Small module for defining record specs.

  # define the opaque type
  @opaque t :: {
    key :: any,
    touched :: number,
    ttl :: number | nil,
    value :: any
  }
end
