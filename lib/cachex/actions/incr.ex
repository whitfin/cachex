defmodule Cachex.Actions.Incr do

  alias Cachex.Actions
  alias Cachex.Actions.Exists
  alias Cachex.LockManager
  alias Cachex.State
  alias Cachex.Util

  def execute(%State{ } = state, key, options \\ []) when is_list(options) do
    Actions.do_action(state, { :incr, [ key, options ] }, fn ->
      amount  = Util.get_opt_number(options, :amount, 1)
      initial = Util.get_opt_number(options, :initial, 0)
      default = Util.create_record(state, key, initial)

      LockManager.write(state, key, fn ->
        existed = Exists.execute(state, key, notify: false)

        try do
          state.cache
          |> :ets.update_counter(key, { 4, amount }, default)
          |> handle_existed(existed)
        rescue
          _e -> { :error, :non_numeric_value }
        end
      end)
    end)
  end

  defp handle_existed(val, { :ok,  true }) do
    { :ok, val }
  end
  defp handle_existed(val, { :ok, false }) do
    { :missing, val }
  end

end
