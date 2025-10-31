defmodule Cachex.Actions.Keys do
  @moduledoc false
  # Command module to allow retrieving keys from a cache.
  #
  # The execution of this command will be quite slow to execute. This is
  # to be expected and so it should be used wisely, or `stream()` should
  # be used instead.
  #
  # This command will take the expiration of entries into consideration.
  alias Cachex.Query

  # we need our imports
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Retrieves a list of all keys in the cache.

  Only keys for entries which have not yet expired will be returned. This means
  that any entries currently inside the cache which are scheduled to be removed
  will not be included.
  """
  def execute(cache(name: name), _options) do
    filter = Query.unexpired()
    clause = Query.build(where: filter, output: :key)

    :ets.select(name, clause)
  end
end
