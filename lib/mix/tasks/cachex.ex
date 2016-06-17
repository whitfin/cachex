defmodule Mix.Tasks.Cachex do
  use Mix.Task

  @moduledoc false
  # A neat Mix Task to automate the wrapping of tasks in a Cachex context. A context
  # will start any Cachex required test nodes so that they're available for testing
  # replication and remote features.
  #
  # The first argument to this task must be the name of the task you wish to run.
  # Any arguments thereafter will be passed directly to that task. This allows
  # you to easily start a test run by doing something like this:
  #
  #   mix cachex test --trace
  #
  # This task exists to make it flexible to run Cachex test-based tools, whereas
  # previously we defined a task per those we recognised, which naturally didn't
  # scale particularly well.

  # import context tools
  import Mix.Cachex

  @doc """
  Provides access to tasks inside a Cachex context.

  This is required as there are several nodes to stop/start for things such as
  test runs. Running via this Task will start the context, run the provided task,
  and then close the context.

  The first argument must always be a task to execute, and any other arguments
  as passed directly through to the Mix Task itself.

  As an example:

      Mix.Tasks.Cachex.run([ "test", "--trace" ])

  will execute the `test` task, with the argument `--trace`.
  """
  @spec run(OptionParser.argv) :: no_return
  def run([task]) do
    run_in_context(task)
  end
  def run([task | args]) do
    run_in_context(task, args)
  end
  def run([]) do
    Mix.raise("A task name must be provided as first argument")
  end

end
