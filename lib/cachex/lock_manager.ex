defmodule Cachex.LockManager do
  @moduledoc false
  # This module controls the interface for dealing with key locking inside the
  # backing ETS table of a cache. We provide grace functions for transactions and
  # lock-aware writes to the table.

  # add some aliases
  alias Cachex.State
  alias Cachex.LockManager.Table

  @doc """
  Detects if the current process is in transactional context.
  """
  def transaction? do
    Process.get(:transactional, false)
  end

  @doc """
  Executes a function inside a transactional context.

  We pass this through to `safe_exec/2` to handle shortcuts if we're inside a
  transactional context already.
  """
  def transaction(%State{ manager: manager }, keys, fun) do
    safe_exec(fun, fn ->
      GenServer.call(manager, { :transaction, keys, fun }, :infinity)
    end)
  end

  @doc """
  Sets whether this process is inside a transactional context.
  """
  def set_transaction(transactional) do
    Process.put(:transactional, !!transactional)
    !!transactional
  end

  @doc """
  Performs a write against the given key inside the table.

  If the key is locked, the write is queued inside the lock server to ensure that
  we execute consistently.
  """
  def write(%State{ transactions: trans } = state, key, fun) do
    if trans do
      do_write(state, key, fun)
    else
      fun.()
    end
  end

  # Execeutes a write, by passing through to the internal `safe_exec/2` function.
  # If we're not in a transaction and the key is writable, we perform our write.
  # Otherwise we queue our write up for execution inside the lock server.
  defp do_write(%State{ cache: cache, manager: manager }, key, fun) do
    safe_exec(fun, fn ->
      if Table.writable?(cache, key) do
        fun.()
      else
        GenServer.call(manager, { :exec, fun }, :infinity)
      end
    end)
  end

  # Executes the function if we're already in a transactional context, otherwise
  # fires the callback to pass the value through to the lock server.
  defp safe_exec(fun, to_exec) do
    transaction?() && fun.() || to_exec.()
  end

end
