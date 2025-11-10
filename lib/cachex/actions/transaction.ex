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
  to the user-defined function, with handles on arity for convenience.
  """
  def execute(cache() = cache, keys, operation, _options) do
    Locksmith.transaction(cache, keys, fn ->
      case :erlang.fun_info(operation)[:arity] do
        0 -> operation.()
        1 -> operation.(cache)
      end
    end)
  end
end
