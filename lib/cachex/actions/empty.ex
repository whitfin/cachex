defmodule Cachex.Actions.Empty do
  @moduledoc false
  # This module controls the action implementation for the `:empty?` command,
  # which checks whether the cache is currently empty or not. This action is
  # currently sugar around the `:size` command, which normalizing the numeric
  # results back into boolean values.

  # we need our imports
  import Cachex.Actions
  import Cachex.Spec

  # add some aliases
  alias Cachex.Cache
  alias Cachex.Actions.Size

  @doc """
  Checks whether the cache contains any records.

  If the cache is not empty, we return a false response. It should be noted here
  that emptiness is determined by overall cache size, regardless of key expiration.
  Thus it may be that you have a non-empty cache, yet be unable to retrieve any
  keys due to on-demand expiration.

  We delegate this action internally to the Size action and simply cast the numeric
  value in the response into a boolean for consumption.

  There are currently no recognised options, the argument only exists for future
  proofing.
  """
  defaction empty?(%Cache{ } = cache, options) do
    cache
    |> Size.execute(const(:notify_false))
    |> handle_size
  end

  # Handles the casting of the size values back into booleans. If the size is
  # more than 0, we return false. If it's 0, we return true. There will never
  # be anything accepted below 0, so we don't need to worry about it.
  defp handle_size({ :ok, 0 }),
    do: { :ok, true }
  defp handle_size(_other_val),
    do: { :ok, false }
end
