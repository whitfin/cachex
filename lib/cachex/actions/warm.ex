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

  You can provide a `:modules` option to restrict the warming to a specific
  set of warmer modules. The list of modules which had a warming triggered will
  be returned in the result of this call.
  """
  def execute(cache(warmers: warmers), options) do
    mods = Keyword.get(options, :modules, nil)

    handlers =
      for warmer(module: mod) <- warmers, mods == nil or mod in mods do
        send(mod, :cachex_warmer) && mod
      end

    {:ok, handlers}
  end
end
