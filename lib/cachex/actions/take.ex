defmodule Cachex.Actions.Take do
  @moduledoc false

  alias Cachex.Actions
  alias Cachex.Hook
  alias Cachex.LockManager
  alias Cachex.State
  alias Cachex.Util

  def execute(%State{ } = state, key, options \\ []) when is_list(options) do
    Actions.do_action(state, { :take, [ key, options ] }, fn ->
      LockManager.write(state, key, fn ->
        state.cache
        |> :ets.take(key)
        |> handle_take(state)
      end)
    end)
  end

  defp handle_take([{ _key, touched, ttl, value }], state) do
    if Util.has_expired?(state, touched, ttl) do
      Hook.broadcast(state.cache, { :purge, [[]] }, { :ok, 1 })
      { :missing, nil }
    else
      { :ok, value }
    end
  end
  defp handle_take(_missing, _cache) do
    { :missing, nil }
  end

end
