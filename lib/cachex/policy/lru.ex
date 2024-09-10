defmodule Cachex.Policy.LRU do
  @moduledoc """
  Least recently used eviction policies for Cachex.

  This module provides basic bindings around `Cachex.Policy.LRW` to adapt the
  LRW caching policies for LRU purposes. As such, please see the documentation
  of `Cachex.Policy.LRW` for a full list of supported options.

  Adding LRU support is done by attaching an additional hook to enable updates
  of the modification time in a cache entry on read. This is a very basic way
  to provide LRU policies, but it should suffice for most cases. It's possible
  that this may change in future, so this implementation should not be relied upon.

  At the time of writing modification times are *not* updated when executing
  commands on multiple keys, such as `Cachex.keys/2` and `Cachex.stream/3`, for
  performance reasons. Again, this may change in future if necessary.
  """
  use Cachex.Hook
  use Cachex.Policy

  # import macros
  import Cachex.Spec

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

  # actions which didn't trigger
  @ignored [:error, :ignore]

  ####################
  # Policy Behaviour #
  ####################

  @doc """
  Configures hooks required to back this policy.
  """
  def hooks(limit() = limit),
    do: [
      hook(
        state: nil,
        module: __MODULE__
      )
      | Cachex.Policy.LRW.hooks(limit)
    ]

  ##################
  # Hook Behaviour #
  ##################

  @doc """
  Returns the actions this policy should listen on.
  """
  @spec actions :: [atom]
  def actions,
    do: @actions

  @doc """
  Returns the provisions this policy requires.
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
  def handle_notify({_action, [key | _]}, {status, _value}, cache)
      when status not in @ignored do
    {:ok, true} = Cachex.touch(cache, key, const(:notify_false))
    {:ok, cache}
  end

  def handle_notify(_event, _result, cache),
    do: {:ok, cache}

  @doc false
  # Receives a provisioned cache instance.
  #
  # The provided cache is then stored in the cache and used for cache calls going
  # forwards, in order to skip the lookups inside the cache overseer for performance.
  def handle_provision({:cache, cache}, _cache),
    do: {:ok, cache}
end
