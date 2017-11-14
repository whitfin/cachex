defmodule Cachex.Actions.Transaction do
  @moduledoc false
  # This module handles the (very) small implementation of Transactions. This
  # is small because we simply pass values through to the Locksmith implementation
  # of transactions, which does the heavy lifting. All that's provided here is a
  # little bit of massaging.

  # add some aliases
  alias Cachex.Services.Locksmith
  alias Cachex.State

  @doc """
  Executes a Transaction against the cache.

  The Locksmith does the heavy lifting here, we just provide the cache state
  to the user's provided function. We wrap the result in an ok Tuple just to
  protect against people unwrapping values using bang functions on the Cachex
  interface.

  There are currently no recognised options, the argument only exists for future
  proofing.
  """
  def execute(%State{ } = state, keys, operation, _options) do
    Locksmith.transaction(state, keys, fn ->
      { :ok, operation.(state) }
    end)
  end
end
