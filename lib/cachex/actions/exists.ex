defmodule Cachex.Actions.Exists do

  alias Cachex.Actions
  alias Cachex.State

  def execute(%State{ } = state, key, options \\ []) when is_list(options) do
    Actions.do_action(state, { :exists?, [ key, options ] }, fn ->
      state
      |> Actions.read(key)
      |> handle_record
    end)
  end

  defp handle_record({ _key, _touched, _ttl, _value }) do
    { :ok, true }
  end
  defp handle_record(_missing) do
    { :ok, false }
  end

end
