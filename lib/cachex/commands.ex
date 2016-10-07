defmodule Cachex.Commands do
  @moduledoc false
  # This module controls basic command parsing for commands provided in options
  # for a cache. This is moved into a separate module in order to make it easier
  # to keep the logic separate. This module does not currently control execution,
  # but just the parsing and validation of provided commands.

  # we need our constants
  use Cachex.Constants

  @doc """
  Parses a Keyword list of commands into a Map of commands.

  This can return an error if there is an invalid command structure inside the
  command list.
  """
  def parse(cmds) when is_list(cmds) do
    with :ok <- validate(cmds), do: { :ok, Enum.into(cmds, %{}) }
  end

  @doc """
  Validates a list of commands and their structure.

  This will stop and return an error on the first instance of an invalid command.
  """
  def validate([ { _, { tag, fun } } | tl ])
  when is_function(fun, 1) and tag in [ :return, :modify ],
    do: validate(tl)
  def validate([ ]),
    do: :ok
  def validate(_inv),
    do: @error_invalid_command

end
