defmodule Cachex.Actions.Refresh do
  @moduledoc """
  Command module to allow refreshing an expiration value.

  Refreshing an expiration is the notion of resetting an expiration time
  as if it were just set. This is done by updating the touched time (as
  this is used to calculate expiration offsets).

  The main advantage of this command is the ability to refresh an existing
  expiration without knowing in advance what it was previously set to.
  """
  alias Cachex.Actions
  alias Cachex.Services.Locksmith

  # we need our imports
  import Cachex.Actions
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Refreshes an expiration on a cache entry.

  If the entry currently has no expiration set, it is left unset. Otherwise the
  touch time of the entry is updated to the current time (as entry expiration is
  a function of touched time and expiration time).

  This operates inside a lock aware context to avoid clashing with other operations
  on the same key during execution.
  """
  defaction refresh(cache() = cache, key, options) do
    Locksmith.write(cache, [ key ], fn ->
      Actions.update(cache, key, entry_mod_now())
    end)
  end
end
