defmodule Cachex.Actions.Update do
  @moduledoc false
  # Command module to update existing cache entries.
  #
  # The only semantic difference between an `update()` call against a `set()`
  # call is that the expiration time remains unchanged during an update. If
  # you wish to have the expiration time modified, you can simply set your
  # new value over the top of the existing one.
  alias Cachex.Actions
  alias Cachex.Services.Locksmith

  # we need our imports
  import Cachex.Actions
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Updates an entry inside the cache.

  Updates do not affect the touch time of a record, which is what makes an update
  call useful. If you need to update the touch time you can either call `touch()`
  immediately after an update, or you can simply set a value over the top instead
  of doing an update.
  """
  defaction update(cache() = cache, key, value, options) do
    Locksmith.write(cache, [ key ], fn ->
      Actions.update(cache, key, entry_mod(value: value))
    end)
  end
end
