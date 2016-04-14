defmodule Mix.Tasks.Cachex.Test do
  # inherit mix tasks
  use Mix.Task

  @moduledoc false
  # A small binding module for running tests - spinning up and slave nodes as
  # required for remote testing. Providing a Mix task for this means that the
  # user doesn't have to care about setting up any node instances.

  @doc """
  Quite simply spawns off a Mix Task to run all tests, after having bound and
  ensured that all slave nodes are started using `Mix.Cachex.run_task/2`.
  """
  @spec run(OptionParser.argv) :: no_return
  def run(args),
  do: Mix.Cachex.run_in_context("test", args)

end
