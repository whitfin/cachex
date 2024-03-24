defmodule Cachex.Actions.Warm do
  @moduledoc false
  # Command module to trigger manual cache warming.
  #
  # The only reason to call this command is the case in which you already
  # know the backing state of your cache has been updated and you need to
  # immediately refresh your warmed entries.
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Triggers a manual warming in a cache.

  The warmers are fetched back out of the supervision tree, by calling out
  to our services module. This allows us to avoid having to track any special
  state in order to support manual warming.

  You can provide an `:only` option to restrict the warming to a specific set
  of warmer modules or names. The list can contain either the name of the
  module, or the name of the registered server. The list of warmer names which
  had a warming triggered will be returned in the result of this call.
  """
  def execute(cache(warmers: warmers), options) do
    only = Keyword.get(options, :only, nil)

    match =
      Enum.filter(warmers, fn warmer(module: mod, name: name) ->
        only == nil or mod in only or name in only
      end)

    warmed =
      for warmer(name: name) <- match do
        send(name, :cachex_warmer) && name
      end

    {:ok, warmed}
  end
end
