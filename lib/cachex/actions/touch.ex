defmodule Cachex.Actions.Touch do
  @moduledoc false

  alias Cachex.Actions
  alias Cachex.Actions.Ttl
  alias Cachex.LockManager
  alias Cachex.State
  alias Cachex.Util

  def execute(%State{ } = state, key, options \\ []) when is_list(options) do
    Actions.do_action(state, { :touch, [ key, options ] }, fn ->
      LockManager.write(state, key, fn ->
        state
        |> Ttl.execute(key, notify: false)
        |> handle_ttl(state, key)
      end)
    end)
  end

  defp handle_ttl({ :missing, nil }, _state, _key) do
    { :missing, false }
  end

  defp handle_ttl({ :ok, nil }, state, key) do
    Actions.update(state, key, [{ 2, Util.now() }])
  end
  defp handle_ttl({ :ok, val }, state, key) do
    Actions.update(state, key, [{ 2, Util.now() }, { 3, val }])
  end

end
