defmodule Cachex.LockManager do

  alias Cachex.State
  alias __MODULE__.Table

  def is_transaction do
    Process.get(:locked, false)
  end

  def transaction(%State{ manager: manager }, keys, fun) when is_function(fun, 0) do
    safe_exec(fun, fn ->
      GenServer.call(manager, { :transaction, keys, fun }, :infinity)
    end)
  end

  def write(%State{ transactions: trans } = state, key, fun) when is_function(fun, 0) do
    if trans do
      do_write(state, key, fun)
    else
      fun.()
    end
  end

  defp do_write(%State{ cache: cache, manager: manager }, key, fun) do
    safe_exec(fun, fn ->
      if Table.writable?(cache, key) do
        fun.()
      else
        GenServer.call(manager, { :exec, fun }, :infinity)
      end
    end)
  end

  defp safe_exec(fun, to_exec) do
    is_transaction() && fun.() || to_exec.()
  end

end
