defmodule Cachex.Limit.Accessed do
  @moduledoc """
  Access based touch tracking for LRW pruning.

  This module can be used to adapt `Cachex.prune/3` for LRU purposes instead of
  the typical LRW. This hook will update the modification time of a cache entry
  upon access by a read operation. This is a very basic way to provide LRU policies,
  but it should suffice for most cases.

  At the time of writing modification times are *not* updated when executing
  commands on multiple keys, such as `Cachex.keys/2` and `Cachex.stream/3`, for
  performance reasons. Again, this may change in future if necessary.
  """
  use Cachex.Hook

  # touched actions
  @actions [
    :decr,
    :exists?,
    :fetch,
    :get,
    :incr,
    :invoke,
    :ttl,
    :update
  ]

  ##################
  # Hook Behaviour #
  ##################

  @doc """
  Returns the actions this hook should listen on.
  """
  @spec actions :: [atom]
  def actions,
    do: @actions

  @doc """
  Returns the provisions this hook requires.
  """
  @spec provisions :: [atom]
  def provisions,
    do: [:cache]

  ####################
  # Server Callbacks #
  ####################

  @doc false
  # Handles notification of a cache action.
  #
  # This will update the modification time of a key if tracked in a successful cache
  # action. In combination with LRW caching, this provides a simple LRU policy.
  def handle_notify({_action, [key | _]}, _result, cache) do
    true = Cachex.touch(cache, key)
    {:ok, cache}
  end

  @doc false
  # Receives a provisioned cache instance.
  #
  # The provided cache is then stored in the cache and used for cache calls going
  # forwards, in order to skip the lookups inside the cache overseer for performance.
  def handle_provision({:cache, cache}, _cache),
    do: {:ok, cache}
end
