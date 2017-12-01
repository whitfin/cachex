defmodule Cachex.Actions.Purge do
  @moduledoc """
  Command module to allow manual purging of expired records.

  This is highly optimized using native ETS behaviour to purge as many
  entries as possible at a high rate. It is used internally by the Janitor
  service when purging on a schedule.
  """
  alias Cachex.Services.Locksmith
  alias Cachex.Util

  # we need our imports
  import Cachex.Actions
  import Cachex.Spec

  @doc """
  Purges all expired records from the cache.

  This is optimizes to use native ETS batch deletes using match specifications,
  which are compiled using the utility functions found in `Cachex.Util`.

  This function is used by the Janitor process internally to sync behaviour in
  both places rather than reimplementing the same logic in two places.

  We naturally need a transaction context to ensure that we don't remove any
  records currently being used in a transaction block.
  """
  defaction purge(cache(name: name) = cache, options) do
    Locksmith.transaction(cache, [ ], fn ->
      { :ok, :ets.select_delete(name, Util.retrieve_expired_rows(true)) }
    end)
  end
end
