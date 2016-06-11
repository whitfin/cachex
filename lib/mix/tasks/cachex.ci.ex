defmodule Mix.Tasks.Cachex.Ci do
  # inherit mix tasks
  use Mix.Task

  @moduledoc """
 A small binding module to run the tasks used in the CI build. This just provides
 a shorthand to allow the developer to easily replicate what the CI build does.
 """

 @doc """
 Starts off all required Mix Tasks for the CI build (we can use our own defined
 Mix Tasks too). A failing Mix Task will cause an early exit, so nothing special
 needs to be done.
 """
  @spec run(OptionParser.argv) :: no_return
  def run(_args) do
    Mix.Task.run("cachex.analyze", [])
    Mix.Task.run("cachex.coveralls", [ "--trace" ])
  end

end
