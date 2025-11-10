defmodule Cachex.Actions.Expire do
  @moduledoc false
  # Command module to allow setting entry expiration.
  #
  # This module is a little more involved than it would be as it's used as a
  # binding for other actions (such as removing expirations). As such, we have
  # to handle several edge cases with nil values.
  alias Cachex.Actions
  alias Cachex.Services.Locksmith

  # add required imports
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Sets the expiration time on a given cache entry.

  This command executes inside a lock aware context to ensure that the key isn't currently
  being used/modified/removed from another process in the application.
  """
  def execute(cache() = cache, key, expiration, _options) do
    Locksmith.write(cache, [key], fn ->
      Actions.update(cache, key, entry_mod_now(expiration: max(0, expiration)))
    end)
  end
end
