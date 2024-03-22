defmodule Cachex.Actions.Warm do
  @moduledoc false
  # Command module to trigger manual cache warming.
  #
  # The only reason to call this command is the case in which you already
  # know the backing state of your cache has been updated and you need to
  # immediately refresh your warmed entries.
  alias Cachex.Services

  # we need our imports
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
  def execute(cache() = cache, options) do
    mods = Keyword.get(options, :modules, nil)
    parent = Services.locate(cache, Services.Incubator)
    children = if parent, do: Supervisor.which_children(parent), else: []

    handlers =
      for {mod, pid, _, _} <- children, mods == nil or mod in mods do
        send(pid, :cachex_warmer) && mod
      end

    {:ok, handlers}
  end
end
