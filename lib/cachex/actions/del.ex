defmodule Cachex.Actions.Del do
  @moduledoc """
  Command module to allow removal of a cache entry.
  """
  alias Cachex.Services.Locksmith

  # import required macros
  import Cachex.Actions
  import Cachex.Spec

  @doc """
  Removes an entry from a cache by key.

  This command will always return a true value, signalling that the key no longer
  exists in the cache (regardless of whether it previously existed).

  Removal runs in a lock aware context, to ensure that we're not removing a key
  being used inside a transaction in other places in the codebase.
  """
  defaction del(cache(name: name) = cache, key, options) do
    Locksmith.write(cache, key, fn ->
      { :ok, :ets.delete(name, key) }
    end)
  end
end
