defmodule Cachex.Test.Hook.Callers do
  use Cachex.Hook
  import Cachex.Spec

  def async?, do: true
  def actions, do: :all
  def type, do: :pre

  @doc """
  Returns a hook definition for a custom execute hook.
  """
  def create(name \\ nil),
    do: hook(module: __MODULE__, args: self(), name: name)

  def handle_notify(_, _, proc) do
    send(proc, Process.get(:"$callers"))
    {:noreply, proc}
  end
end
