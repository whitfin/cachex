defmodule Cachex.Actions.Update do
  @moduledoc false

  alias Cachex.Actions
  alias Cachex.LockManager
  alias Cachex.State

  def execute(%State{ } = state, key, value, options \\ []) when is_list(options) do
    Actions.do_action(state, { :update, [ key, value, options ] }, fn ->
      LockManager.write(state, key, fn ->
        Actions.update(state, key, [{ 4, value }])
      end)
    end)
  end

end
