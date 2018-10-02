defmodule Cachex.Actions.Purge do
  @moduledoc false
  # Command module to allow manual purging of expired records.
  #
  # This is highly optimized using native ETS behaviour to purge as many
  # entries as possible at a high rate. It is used internally by the Janitor
  # service when purging on a schedule.
  alias Cachex.Query
  alias Cachex.Services.Locksmith

  # we need our imports
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Purges all expired records from the cache.

  This is optimizes to use native ETS batch deletes using match specifications,
  which are compiled using the utility functions found in `Cachex.Query`.

  This function is used by the Janitor process internally to sync behaviour in
  both places rather than reimplementing the same logic in two places.

  We naturally need a transaction context to ensure that we don't remove any
  records currently being used in a transaction block.
  """
  def execute(cache(name: name) = cache, _options) do
    Locksmith.transaction(cache, [ ], fn ->
      { :ok, :ets.select_delete(name, Query.expired(true)) }
    end)
  end
end
