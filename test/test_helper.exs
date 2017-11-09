# ensure that Cachex has been started
Application.ensure_all_started(:cachex)

# require test lib files
"#{Path.dirname(__ENV__.file)}/lib/**/*"
|> Path.wildcard
|> Enum.filter(&!File.dir?(&1))
|> Enum.each(&Code.require_file/1)

# start ExUnit!
ExUnit.start()

# internal module
defmodule TestHelper do
  @moduledoc false
  # This module exists because we need a contextual helper in order to be able
  # to execute the ExUnit callbacks. Therefore this module is just a wrapper of
  # these callbacks.

  # test context
  require ExUnit.Case

  @doc false
  # Schedules a cache to be deleted at the end of the current test context.
  def delete_on_exit(name) do
    ExUnit.Callbacks.on_exit("delete #{name}", fn ->
      try do
        Supervisor.stop(name)
      catch
        :exit, _ -> :ok
      end
    end)
  end
end
