defmodule Cachex.Actions.Ttl do

  alias Cachex.Actions
  alias Cachex.State
  alias Cachex.Util

  def execute(%State{ } = state, key, options \\ []) when is_list(options) do
    Actions.do_action(state, { :ttl, [ key, options ] }, fn ->
      state
      |> Actions.read(key)
      |> handle_record
    end)
  end

  defp handle_record({ _key, _touched, nil, _value }) do
    { :ok, nil }
  end
  defp handle_record({ _key, touched, ttl, _value }) do
    { :ok, touched + ttl - Util.now() }
  end
  defp handle_record(_missing) do
    { :missing, nil }
  end

end
