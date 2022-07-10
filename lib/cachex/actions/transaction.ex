defmodule Cachex.Actions.Transaction do
  @moduledoc false
  # Command module to enable transactional execution against a cache.
  #
  # This command handles the (very) small implementation of transactions. The
  # reason for it being so small is that we simply pass values through to the
  # Locksmith service to do the heavy lifting. All that's provided here is a
  # little bit of massaging.
  alias Cachex.Services.Locksmith

  # import records
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Executes a transaction against the cache.

  The Locksmith does most of the work here, we just provide the cache state
  to the user-defined function. The results are wrapped in an `:ok` tagged
  Tuple just to protect against internally unwrapped values from bang functions.
  """
  def execute(cache() = cache, keys, operation, _options) do
    Locksmith.transaction(cache, keys, fn ->
      {:ok, operation.(cache)}
    end)
  end
end
