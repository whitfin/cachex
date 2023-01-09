defmodule Cachex.Policy.LRW.Evented do
  @moduledoc """
  Evented least recently written eviction policy for Cachex.

  This module implements an evented LRW eviction policy for Cachex, using a hook
  to listen for new key additions to a cache and enforcing bounds in a reactive
  way. This policy enforces cache bounds and limits far more accurately than other
  scheduled implementations, but comes at a higher memory cost (due to the message
  passing between hooks).

  The `:batch_size` option can be set in the limit options to dictate how many
  entries should be removed at once by this policy. This will default to a batch
  size of 100 entries at a time.

  This eviction is relatively fast, and should keep the cache below bounds at most
  times. Note that many writes in a very short amount of time can flood the cache,
  but it should recover given a few seconds.
  """
  use Cachex.Hook
  use Cachex.Policy

  # import macros
  import Cachex.Spec

  # add internal aliases
  alias Cachex.Policy.LRW

  # actions which didn't trigger a write
  @ignored [:error, :ignored]

  ####################
  # Policy Behaviour #
  ####################

  @doc """
  Retrieves a list of hooks required to run against this policy.
  """
  @spec hooks(Spec.limit()) :: [Spec.hook()]
  def hooks(limit),
    do: [hook(module: __MODULE__, state: limit)]

  ######################
  # Hook Configuration #
  ######################

  @doc """
  Returns the actions this policy should listen on.

  This returns as a `MapSet` to optimize the lookups
  on actions to O(n) in the broadcasting algorithm.
  """
  @spec actions :: [atom]
  def actions,
    do: [
      :put,
      :decr,
      :incr,
      :fetch,
      :update,
      :put_many,
      :get_and_update
    ]

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
  # Initializes this policy using the limit being enforced.
  #
  # The maximum size is stored in the state, alongside the pre-calculated
  # number to trim down to. The batch size to use when removing records is
  # also configurable via the provided options.
  def init(limit() = limit),
    do: {:ok, {nil, limit}}

  @doc false
  # Handles notification of a cache action.
  #
  # This will check if the action can modify the size of the cache, and if so will
  # execute the boundary enforcement to trim the size as needed.
  #
  # Note that this will ignore error results and only operates on actions which are
  # able to cause a net gain in cache size (so removals are also ignored).
  def handle_notify(_message, {status, _value}, {cache, limit} = opts)
      when status not in @ignored,
      do: LRW.enforce_bounds(cache, limit) && {:ok, opts}

  def handle_notify(_message, _result, opts),
    do: {:ok, opts}

  @doc false
  # Receives a provisioned cache instance.
  #
  # The provided cache is then stored in the cache and used for cache calls going
  # forwards, in order to skip the lookups inside the cache overseer for performance.
  def handle_provision({:cache, cache}, {_cache, limit}),
    do: {:ok, {cache, limit}}
end
