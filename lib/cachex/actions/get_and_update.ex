defmodule Cachex.Actions.GetAndUpdate do
  @moduledoc """
  Command module to enable transactional get/update semantics.

  This command is simply sugar, but is common enough that it deserved an explicit
  implementation inside the API. It does take care of the transactional context
  of the get/update semantics though, so it's potentially non-obvious.
  """
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
      { status, value } = Get.execute(cache, key, const(:notify_false))

      value
      |> update_fun.()
      |> normalize_commit
      |> handle_commit(cache, key, status)
    end)
  end

  ###############
  # Private API #
  ###############

  # Handles a commit Tuple to ensure persistence.
  #
  # If the Tuple is tagged with the `:ignore` atom, it is not persisted and it
  # simply returned as-is. If it's tagged as `:commit`, we use the status from
  # the initial `get()` call to determine if we need to update or set the value.
  defp handle_commit({ :ignore, tempv }, _cache, _key, status),
    do: { status, tempv }
  defp handle_commit({ :commit, tempv }, cache, key, status) do
    write_mod(status).execute(cache, key, tempv, const(:notify_false))
    { status, tempv }
  end
end
