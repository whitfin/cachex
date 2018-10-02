defmodule Cachex.Actions.GetAndUpdate do
  @moduledoc false
  # Command module to enable transactional get/update semantics.
  #
  # This command is simply sugar, but is common enough that it deserved an explicit
  # implementation inside the API. It does take care of the transactional context
  # of the get/update semantics though, so it's potentially non-obvious.
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
  def execute(cache() = cache, key, update_fun, _options) do
    Locksmith.transaction(cache, [ key ], fn ->
      { _label, value } = Cachex.get(cache, key, [])

      normalized =
        value
        |> update_fun.()
        |> normalize_commit

      with { :commit, new_value } <- normalized do
        apply(Cachex, write_op(value), [cache, key, new_value, []])
      end

      normalized
    end)
  end
end
