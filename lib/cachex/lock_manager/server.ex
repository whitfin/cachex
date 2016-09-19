defmodule Cachex.LockManager.Server do
  @moduledoc false
  # This module contains the backing GenServer process for the LockManager which
  # handles all writes to the ETS tables which execute in a locked context. There
  # are two interfaces here; a transactional call which will automatically handle
  # table locking on the keys being worked on, and a simple execution interface.
  # The execution interface does little beyond execute the provided function, but
  # it provides the guarantee that the function is exeuting at a time when there
  # are no locks currently held on the table. This has the advantage of allowing
  # writes to act eagerly but back up into this process if they hit a key lock.

  # inherit GenServer
  use GenServer

  # add some aliases
  alias Cachex.LockManager
  alias Cachex.LockManager.Table
  alias Cachex.Util.Names

  @doc """
  Starts a process to handle transactional calls.
  """
  def start_link(cache) do
    GenServer.start_link(__MODULE__, cache, [
      name: Names.manager(cache)
    ])
  end

  @doc """
  Sets the current process as transactional and returns the cache as the state.
  """
  def init(cache) do
    # signal this process as transactional
    LockManager.set_transaction(true)
    # return the cache as our state
    { :ok, cache }
  end

  @doc """
  Executes a function in a lock-free context.

  Because locks are handled sequentially inside this process, this execution can
  guarantee that there are no locks currently set on the table when it fires.
  """
  def handle_call({ :exec, fun }, _ctx, cache) do
    { :reply, do_exec(fun), cache }
  end

  @doc """
  Executes a function in a transactional context.

  This will lock any required keys before carrying out any writes, and then remove
  the locks. The key here is that locks on a key will stop other processes from
  writing them, and forcing those processes to queue their writes up inside this
  process.
  """
  def handle_call({ :transaction, keys, fun }, _ctx, cache) do
    { :reply, Table.transaction(cache, keys, fn -> do_exec(fun) end), cache }
  end

  # Simply a wrapper around provided functions to ensure that error handling is
  # provided appropriately. Any errors which occur in the execution of the given
  # function are rescued and returned in an error Tuple.
  defp do_exec(fun) do
    fun.()
  rescue
    e -> { :error, Exception.message(e) }
  end

end
