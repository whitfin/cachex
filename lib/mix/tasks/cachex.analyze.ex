defmodule Mix.Tasks.Cachex.Analyze do
  # inherit mix tasks
  use Mix.Task

  @moduledoc false
  # A small binding module to run static-code analysis on the application using a
  # shorthand to invoke Credo with all issues in single line format.

  @doc """
  Quite simply spawns off a Mix Task to run the Credo task with the specified
  formats and configurations.
  """
  @spec run(OptionParser.argv) :: no_return
  def run(args) do
    Mix.Task.run("credo", args ++ [ "--all", "--format=oneline" ])
  end

end
