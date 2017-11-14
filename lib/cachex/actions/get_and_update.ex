defmodule Cachex.Actions.GetAndUpdate do
  @moduledoc false
  # This module provides an implementation for the GetAndUpdate action, which
  # is actually just sugar for get/set inside a Transaction. We therefore ensure
  # that everything runs inside a Transaction to guarantee that the key is locked.

  # we need our imports
  use Cachex.Actions

  # add some action aliases
  alias Cachex.Actions.Get

  # add other aliases
  alias Cachex.Services.Locksmith
  alias Cachex.State
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
  defaction get_and_update(%State{ } = state, key, update_fun, options) do
    Locksmith.transaction(state, [ key ], fn ->
      { status, value } = Get.execute(state, key, @notify_false)

      value
      |> update_fun.()
      |> Util.normalize_commit
      |> handle_commit(state, key, status)
    end)
  end

  # Handles a commit Tuple, writing the value to the table only if the Tuple is
  # tagged with `:commit` rather than `:ignore`. The same value is returned either
  # way, just that one does not write to the cache.
  defp handle_commit({ :ignore, tempv }, _state, _key, status),
    do: { status, tempv }
  defp handle_commit({ :commit, tempv }, state, key, status) do
    Util
      .write_mod(status)
      .execute(state, key, tempv, @notify_false)

    { status, tempv }
  end
end
