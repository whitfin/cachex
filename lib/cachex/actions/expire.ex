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

  If a negative expiration time is provided, the entry is immediately removed
  from the cache (as it means we have already expired). If a positive expiration
  time is provided, we update the touch time on the entry and update the expiration
  to the one provided.

  If the expiration provided is nil, we need to remove the expiration; so we update
  in the exact same way. This is done passively due to the fact that Erlang term order
  determines that `nil > -1 == true`.

  This command executes inside a lock aware context to ensure that the key isn't currently
  being used/modified/removed from another process in the application.
  """
  def execute(cache() = cache, key, expiration, _options) do
    Locksmith.write(cache, [key], fn ->
      case expiration > -1 do
        true ->
          Actions.update(cache, key, entry_mod_now(expiration: expiration))

        false ->
          Cachex.del(cache, key, const(:purge_override))
      end
    end)
  end
end
