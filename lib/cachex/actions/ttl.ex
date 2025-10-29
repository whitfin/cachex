defmodule Cachex.Actions.Ttl do
  @moduledoc false
  # Command module to retrieve the TTL for a cache entry.
  #
  # TTL retrieval for cache records is determined by calculating the offset
  # between the touch time and the expiration set against an entry instance.
  #
  # Lazy expiration is also taken into account in this module to avoid giving
  # negative TTL values back to the caller.
  alias Cachex.Actions

  # we need our imports
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Retrieves the remaining TTL for a cache item.

  If a cache entry has no expiration set a nil value will be returned, otherwise
  the offset is determined from the record fields and returned to the caller.
  """
  def execute(cache() = cache, key, _options) do
    case Actions.read(cache, key) do
      entry(modified: modified, expiration: exp) when not is_nil(exp) ->
        modified + exp - now()

      _anything_else ->
        nil
    end
  end
end
