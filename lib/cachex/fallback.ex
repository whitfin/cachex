defmodule Cachex.Fallback do
  @moduledoc false
  # This module just contains the struct definitions of a `Cachex.Fallback` model,
  # in order to provide an easy way to move fallback options around without relying
  # on Tuples or Keyword Lists.

  # internal structure
  defstruct [
    state: nil,   # the state to provide to a fallback
    action: nil   # the action a fallback should take
  ]

  # our opaque type
  @opaque t :: %__MODULE__{ }

  @doc """
  Parses an input into a Fallback struct.

  We expect a list of options and use them to derive the Fallback. If anything
  other than options are provided, we just return a default structure.
  """
  def parse(options) when is_list(options),
    do: %__MODULE__{
      state:  Keyword.get(options, :state),
      action: Cachex.Util.get_opt(options, :action, &is_function/1)
    }
  def parse(_options),
    do: %__MODULE__{ }

end
