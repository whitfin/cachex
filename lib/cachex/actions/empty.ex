defmodule Cachex.Actions.Empty do
  @moduledoc """
  Command module to allow checking for cache population.

  This command is basically just sugar around the `size()` command by turning
  the response into a boolean. This means that expiration of records is not
  taken into account (lazy expiration has no effect here).
  """
  alias Cachex.Actions.Size

  # we need our imports
  import Cachex.Actions
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Checks whether any entries exist in the cache.

  Emptiness is determined by the overall size of the cache, regardless of the
  expiration times set alongside keys. This means that you may have a non-empty
  cache, yet be unable to retrieve any keys due to having lazy expiration enabled.

  Internally this action is delegated through to the `size()` command and the
  returned numeric value is just "cast" to a boolean value.
  """
  defaction empty?(cache() = cache, options) do
    { :ok, size } = Size.execute(cache, const(:notify_false))
    { :ok, size == 0 }
  end
end
