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
  alias Cachex.LockManager
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

  The actions accepted here are those accepted by the `:get` actions, as none
  are used internally and all are forwarded through. This means that this function
  will support fallback values.
  """
  defaction get_and_update(%State{ } = state, key, update_fun, options) do
    LockManager.transaction(state, [ key ], fn ->
      { status, value } = Get.execute(state, key, @notify_false ++ options)

      tempv = update_fun.(value)

      Util
        .write_mod(status)
        .execute(state, key, tempv, @notify_false)

      { status, tempv }
    end)
  end

end
