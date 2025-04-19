defmodule Cachex.Test.Warmer.Callers do
  use Cachex.Warmer

  def execute(proc) do
    send(proc, Process.get(:"$callers"))
    {:ok, []}
  end
end
