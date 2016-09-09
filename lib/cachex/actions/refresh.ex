defmodule Cachex.Actions.Refresh do

  alias Cachex.Actions
  alias Cachex.LockManager
  alias Cachex.State
  alias Cachex.Util

  def execute(%State{ } = state, key, options \\ []) when is_list(options) do
    Actions.do_action(state, { :refresh, [ key, options ] }, fn ->
      LockManager.write(state, key, fn ->
        Actions.update(state, key, [{ 2, Util.now() }])
      end)
    end)
  end

end
