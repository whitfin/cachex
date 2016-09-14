defmodule Cachex.Actions.Incr do
  @moduledoc false

  alias Cachex.Actions
  alias Cachex.Actions.Exists
  alias Cachex.LockManager
  alias Cachex.Record
  alias Cachex.State
  alias Cachex.Util

  def execute(%State{ } = state, key, options \\ []) when is_list(options) do
    Actions.do_action(state, { :incr, [ key, options ] }, fn ->
      amount  = Util.get_opt(options, :amount,  &is_integer/1, 1)
      initial = Util.get_opt(options, :initial, &is_integer/1, 0)
      default = Record.create(state, key, initial)

      LockManager.write(state, key, fn ->
        existed = Exists.execute(state, key, notify: false)

        try do
          state.cache
          |> :ets.update_counter(key, { 4, amount }, default)
          |> handle_existed(existed)
        rescue
          _e -> Cachex.Errors.non_numeric_value()
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
