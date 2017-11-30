defmodule Cachex.Actions.GetAndUpdate do
  @moduledoc false
  # This module provides an implementation for the GetAndUpdate action, which
  # is actually just sugar for get/set inside a Transaction. We therefore ensure
  # that everything runs inside a Transaction to guarantee that the key is locked.

  # we need our imports
  import Cachex.Actions
  import Cachex.Spec

  # add some aliases
  alias Cachex.Actions.Get
  alias Cachex.Services.Locksmith
  alias Cachex.Util

  @doc """
  Retrieves a value and updates it inside the cache.

  This is basically all sugar for `transaction -> set(fun(get()))` but it provides
  an easy-to-use way to update a value directly in the cache. Naturally this
  means that the key needs to be locked and so we use a Transaction to guarantee
  this.

  If the key is not returned by the call to `:get`, then we have to set the new
  value in the cache directly. If it does exist, then we use the update actions
  to update the existing record.
  """
  defaction get_and_update(cache() = cache, key, update_fun, options) do
    Locksmith.transaction(cache, [ key ], fn ->
      { status, value } = Get.execute(cache, key, const(:notify_false))

      value
      |> update_fun.()
      |> Util.normalize_commit
      |> handle_commit(cache, key, status)
    end)
  end

  # Handles a commit Tuple, writing the value to the table only if the Tuple is
  # tagged with `:commit` rather than `:ignore`. The same value is returned either
  # way, just that one does not write to the cache.
  defp handle_commit({ :ignore, tempv }, _cache, _key, status),
    do: { status, tempv }
  defp handle_commit({ :commit, tempv }, cache, key, status) do
    Util
      .write_mod(status)
      .execute(cache, key, tempv, const(:notify_false))

    { status, tempv }
  end
end
