defmodule Cachex.Actions.Expire do
  @moduledoc false

  alias Cachex.Actions
  alias Cachex.Actions.Del
  alias Cachex.LockManager
  alias Cachex.State
  alias Cachex.Util

  def execute(%State{ } = state, key, expiration, options \\ []) when is_list(options) do
    Actions.do_action(state, { :expire, [ key, expiration, options ] }, fn ->
      LockManager.write(state, key, fn ->
        do_expire(state, key, expiration)
      end)
    end)
  end

  defp do_expire(state, key, exp) when exp == nil or exp > 0 do
    Actions.update(state, key, [{ 2, Util.now() }, { 3, exp }])
  end
  defp do_expire(state, key, _exp) do
    Del.execute(state, key, via: :purge)
  end

end
