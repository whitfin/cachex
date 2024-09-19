defmodule Cachex.LRW.Scheduled do
  @moduledoc """
  Scheduled least recently written eviction policy for Cachex.

  This module implements a scheduled LRW eviction policy for Cachex, using a basic
  timer to trigger bound enforcement in a repeatable way. This has the same bound
  accuracy as `Cachex.Policy.LRW.Evented`, but has potential for some delay. The
  main advantage of this implementation is a far lower memory cost due to not
  using hook messages.
  """
  use Cachex.Hook

  # add internal aliases
  alias Cachex.LRW

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
  def init({size, pruning, scheduling} = args)
      when is_integer(size) and is_list(pruning) and is_list(scheduling),
      do: {schedule(scheduling), {nil, args}}

  @doc false
  # Handles notification of a cache action.
  #
  # This will execute a bounds check on a cache and schedule a new check.
  def handle_info(:policy_check, {cache, {size, pruning, scheduling}} = args) do
    LRW.prune(cache, size, pruning)
    schedule(scheduling) && {:noreply, args}
  end

  @doc false
  # Receives a provisioned cache instance.
  #
  # The provided cache is then stored in the state and used for cache calls going
  # forwards, in order to skip the lookups inside the cache overseer for performance.
  def handle_provision({:cache, cache}, {_cache, args}),
    do: {:ok, {cache, args}}

  ###############
  # Private API #
  ###############

  # Schedules a check to occur after the designated interval.
  defp schedule(options) do
    options
    |> Keyword.get(:frequency, 1000)
    |> :erlang.send_after(self(), :policy_check)

    :ok
  end
end
