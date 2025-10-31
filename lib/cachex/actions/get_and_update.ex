defmodule Cachex.Actions.GetAndUpdate do
  @moduledoc false
  # Command module to enable transactional get/update semantics.
  #
  # This command is simply sugar, but is common enough that it deserved an explicit
  # implementation inside the API. It does take care of the transactional context
  # of the get/update semantics though, so it's potentially non-obvious.
  alias Cachex.Actions
  alias Cachex.Services.Locksmith

  # add needed imports
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
  def execute(cache() = cache, key, update_fun, _options) do
    Locksmith.transaction(cache, [key], fn ->
      value = Cachex.get(cache, key, [])

      formatted =
        value
        |> update_fun.()
        |> Actions.format_fetch_value()

      operation = Actions.write_op(value)
      normalized = Actions.normalize_commit(formatted)

      with {:commit, new_value, options} <- normalized do
        apply(Cachex, operation, [cache, key, new_value, options])
        {:commit, new_value}
      end
    end)
  end
end
