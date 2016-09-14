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

  @doc """
  Creates an input record based on a key, value and expiration.

  If the value passed is nil, then we apply any defaults. Otherwise we add the value
  to the current time (in milliseconds) and return a Tuple for the table.
  """
  @spec create(state :: State.t, key :: any, value :: any, expiration :: number | nil) :: Record.t
  def create(%Cachex.State{ } = state, key, value, expiration \\ nil) do
    { key, Cachex.Util.now(), expiration || state.default_ttl, value }
  end

end
