defmodule Cachex.Actions.GetAndUpdate do
  @moduledoc false
  # This module provides an implementation for the GetAndUpdate action, which
  # is actually just sugar for get/set inside a Transaction. We therefore ensure
  # that everything runs inside a Transaction to guarantee that the key is locked.

  # we need our imports
  use Cachex.Actions

  # add some action aliases
  alias Cachex.Actions.Get
  alias Cachex.Actions.Set
  alias Cachex.Actions.Update

  # add other aliases
  alias Cachex.LockManager
  alias Cachex.State

  @doc """
  Retrieves a value and updates it inside the cache.

  This is basically all sugar for `transaction -> set(fun(get()))` but it provides
  an easy-to-use way to update a value directly in the cache. Naturally this
  means that the key needs to be locked and so we use a Transaction to guarantee
  this.

  If the key is not returned by the call to `:get`, then we have to set the new
  value in the cache directly. If it does exist, then we use the update actions
  to update the existing record.

  The actions accepted here are those accepted by the `:get` actions, as none
  are used internally and all are forwarded through. This means that this function
  will support fallback values.
  """
  defaction get_and_update(%State{ } = state, key, update_fun, options) do
    LockManager.transaction(state, [ key ], fn ->
      { status, value } = Get.execute(state, key, @notify_false ++ options)

      tempv = update_fun.(value)

      write_mod(status, state, key, tempv)

      { status, tempv }
    end)
  end

  # Writes the record using the appropriate function. If the key exists in the
  # cache, we use an update operation, otherwise we use a set operation. This
  # is kinda ugly because they both use the same arguments, but rather than using
  # an `apply/3` call this should be a little more performant.
  defp write_mod(:missing, state, key, tempv),
    do: Set.execute(state, key, tempv, @notify_false)
  defp write_mod(_others_, state, key, tempv),
    do: Update.execute(state, key, tempv, @notify_false)

end
