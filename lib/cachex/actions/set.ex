defmodule Cachex.Actions.Set do

  alias Cachex.Actions
  alias Cachex.LockManager
  alias Cachex.State
  alias Cachex.Util

  def execute(%State{ } = state, key, value, options \\ []) when is_list(options) do
    Actions.do_action(state, { :set, [ key, value, options ] }, fn ->
      ttlval = Util.get_opt_number(options, :ttl)
      record = Util.create_record(state, key, value, ttlval)

      LockManager.write(state, key, fn ->
        Actions.write(state, record)
      end)
    end)
  end

end
