defmodule Cachex.Util.Names do
  @moduledoc false
  # This module contains utility functions to generate the names of components
  # inside a cache Supervisor. Rather than duplicate the logic wherever needed,
  # it makes sense to have this stored in a single place to try and treat each
  # component in the same way. We compile the suffixes just because they should
  # be seen as constants.

  # add an alias
  import Cachex.Util

  # our component suffixes
  @eternal_suffix "_eternal"
  @janitor_suffix "_janitor"
  @manager_suffix "_manager"
  @stats_suffix   "_stats"

  @doc """
  Generates a component name for a Cachex Eternal table.
  """
  def eternal(name), do: atom_append(name, @eternal_suffix)

  @doc """
  Generates a component name for a Cachex Janitor process.
  """
  def janitor(name), do: atom_append(name, @janitor_suffix)

  @doc """
  Generates a component name for a Cachex Manager process.
  """
  def manager(name), do: atom_append(name, @manager_suffix)

  @doc """
  Generates a component name for a Cachex Stats process.
  """
  def stats(name), do: atom_append(name, @stats_suffix)

end
