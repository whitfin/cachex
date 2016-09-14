defmodule Cachex.Actions.Set do
  @moduledoc false

  alias Cachex.Actions
  alias Cachex.LockManager
  alias Cachex.Record
  alias Cachex.State
  alias Cachex.Util

  def execute(%State{ } = state, key, value, options \\ []) when is_list(options) do
    Actions.do_action(state, { :set, [ key, value, options ] }, fn ->
      ttlval = Util.get_opt(options, :ttl, &is_integer/1)
      record = Record.create(state, key, value, ttlval)

      LockManager.write(state, key, fn ->
        Actions.write(state, record)
      end)
    end)
  end

end
