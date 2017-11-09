defmodule Cachex.Macros do
  @moduledoc false
  # Provides a number of Macro utilities to make it more convenient to write new
  # Macros. This module is a parent of various submodules which provide Macros
  # for specific uses (to avoid bloating requires and imports). I'm pretty new
  # to Macros so if anything in here (or in submodules) can be done more efficiently,
  # feel free to suggest.

  @doc """
  Trim all defaults from a set of arguments.
  """
  @spec trim_defaults(Macro.t) :: Macro.t
  def trim_defaults(arguments) do
    Enum.map(arguments, fn
      ({ :\\, _, [ arg | _ ] }) -> arg
      (arg) -> arg
    end)
  end

  @doc """
  Retrieves the name, arguments and optional guards for a definition.
  """
  @spec unpack_head(Macro.t) :: { atom, Macro.t, Macro.t | nil }
  def unpack_head({ :when, _, [ { name, _, arguments } | [ condition ] ] }),
    do: { name, arguments, condition }
  def unpack_head({ name, _, arguments }),
    do: { name, arguments, nil }
end
