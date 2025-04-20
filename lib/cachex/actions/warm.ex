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
    wait = Keyword.get(options, :wait, false)

    warmed =
      warmers
      |> Enum.filter(&filter_mod(&1, only))
      |> Enum.map(&spawn_call(&1, wait))
      |> Task.yield_many(:infinity)
      |> Enum.map(&extract_name/1)

    {:ok, warmed}
  end

  ###############
  # Private API #
  ###############

  # Filters warmers based on the :only flag for module/name.
  defp filter_mod(warmer(module: mod, name: name), only),
    do: only == nil or mod in only or name in only

  # Spawns a task to invoke the call to the remote warmer.
  defp spawn_call(warmer(name: name) = warmer, wait) do
    Task.async(fn ->
      call_warmer(warmer, wait)
      name
    end)
  end

  # Invokes a warmer with blocking enabled.
  defp call_warmer(warmer(name: name), true) do
    GenServer.call(name, {:cachex_warmer, get_callers()}, :infinity)
  end

  # Invokes a warmer with blocking disabled.
  defp call_warmer(warmer(name: name), _) do
    callers = get_callers()
    send(name, {:cachex_warmer, callers})
  end

  # Converts a task result to a name reference.
  defp extract_name({_, {:ok, name}}),
    do: name
end
