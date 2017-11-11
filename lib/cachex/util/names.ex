defmodule Cachex.Util.Names do
  @moduledoc false
  # This module contains utility functions to generate the names of components
  # inside a cache Supervisor. Rather than duplicate the logic wherever needed,
  # it makes sense to have this stored in a single place to try and treat each
  # component in the same way. We compile the suffixes just because they should
  # be seen as constants.

  @doc """
  Generates a component name for a Cachex Eternal table.
  """
  def eternal(name),
    do: :"#{name}_eternal"

  @doc """
  Generates a component name for a Cachex Janitor process.
  """
  def janitor(name),
    do: :"#{name}_janitor"

  @doc """
  Generates a component name for a Cachex Locksmith process.
  """
  def locksmith(name),
    do: :"#{name}_locksmith"

  @doc """
  Generates a component name for a Cachex Stats process.
  """
  def stats(name),
    do: :"#{name}_stats"

end
