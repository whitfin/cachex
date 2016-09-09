defmodule Cachex.Actions.Del do
  @moduledoc false

  alias Cachex.Actions
  alias Cachex.LockManager
  alias Cachex.State

  def execute(%State{ } = state, key, options \\ []) when is_list(options) do
    Actions.do_action(state, { :del, [ key, options ] }, fn ->
      LockManager.write(state, key, fn ->
        { :ok, :ets.delete(state.cache, key) }
      end)
    end)
  end

end
