defmodule Cachex.Util.Names do
  @moduledoc false

  @eternal_suffix "_eternal"
  @janitor_suffix "_janitor"
  @manager_suffix "_manager"
  @stats_suffix   "_stats"

  def eternal(name), do: create(name, @eternal_suffix)
  def janitor(name), do: create(name, @janitor_suffix)
  def manager(name), do: create(name, @manager_suffix)
  def stats(name),   do: create(name, @stats_suffix)

  defp create(name, suffix) do
    Cachex.Util.atom_append(name, suffix)
  end

end
