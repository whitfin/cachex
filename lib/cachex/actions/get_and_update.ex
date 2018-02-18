defmodule Cachex.Actions.GetAndUpdate do
  @moduledoc false
  # Command module to enable transactional get/update semantics.
  #
  # This command is simply sugar, but is common enough that it deserved an explicit
  # implementation inside the API. It does take care of the transactional context
  # of the get/update semantics though, so it's potentially non-obvious.
  alias Cachex.Actions.Get
  alias Cachex.Services.Locksmith

  # add needed imports
  import Cachex.Actions
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Retrieves an entry and updates it inside the cache.

  This is basically all sugar for `transaction -> set(fun(get()))` but it provides
  an easy-to-use way to update a value directly in the cache. Naturally this
  means that the key needs to be locked and so we use a transaction to provide
  this guarantee.

  If the key is not returned by the call to `:get`, then we have to set the new
  value in the cache directly. If it does exist, then we use the update actions
  to update the existing record.
  """
  defaction get_and_update(cache() = cache, key, update_fun, options) do
    Locksmith.transaction(cache, [ key ], fn ->
      { _label, value } = Get.execute(cache, key, [])

      normalized =
        value
        |> update_fun.()
        |> normalize_commit

      with { :commit, new_value } <- normalized do
        write_mod(value).execute(cache, key, new_value, [])
      end

      normalized
    end)
  end
end
