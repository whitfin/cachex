defmodule Cachex.Policy.LRW.Scheduled do
  @moduledoc """
  Schedule least recently written eviction policy for Cachex.

  This module implements an evented LRW eviction policy for Cachex, using a basic
  timer to trigger bound enforcement in a scheduled way. This has the same bound
  accuracy as `Cachex.Policy.LRW.Evented`, but has potential for some delay. The
  main advantage of this implementation is a far lower memory cost due to not
  using hook messages.

  The `:batch_size` option can be set in the limit options to dictate how many
  entries should be removed at once by this policy. This will default to a batch
  size of 100 entries at a time.

  The `:frequency` option can also be set in the limit options to specify how
  frequently this policy will fire. This defaults to every few seconds (but may
  change at any point).

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
  """
  @spec actions :: [atom]
  def actions,
    do: []

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
  def init(limit() = limit),
    do: {schedule(limit), {nil, limit}}

  @doc false
  # Handles notification of a cache action.
  #
  # This will execute a bounds check on a cache and schedule a new check.
  def handle_info(:policy_check, {cache, limit} = opts) do
    unless is_nil(cache) do
      LRW.enforce_bounds(cache, limit)
    end

    schedule(limit) && {:noreply, opts}
  end

  @doc false
  # Receives a provisioned cache instance.
  #
  # The provided cache is then stored in the cache and used for cache calls going
  # forwards, in order to skip the lookups inside the cache overseer for performance.
  def handle_provision({:cache, cache}, {_cache, limit}),
    do: {:ok, {cache, limit}}

  ###############
  # Private API #
  ###############

  # Schedules a check to occur after the designated interval.
  defp schedule(limit(options: options)) do
    options
    |> Keyword.get(:frequency, 1000)
    |> :erlang.send_after(self(), :policy_check)

    :ok
  end
end
