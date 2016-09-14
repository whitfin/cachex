defmodule Cachex.LockManager.Server do
  @moduledoc false

  use GenServer

  alias Cachex.LockManager.Table
  alias Cachex.Util.Names

  def start_link(cache) do
    GenServer.start_link(__MODULE__, cache, [ name: Names.manager(cache) ])
  end

  def init(cache) do
    Process.put(:locked, true)
    { :ok, cache }
  end

  def handle_call({ :exec, fun }, _ctx, cache) do
    { :reply, do_exec(fun), cache }
  end

  def handle_call({ :transaction, keys, fun }, _ctx, cache) do
    { :reply, Table.transaction(cache, keys, fn -> do_exec(fun) end), cache }
  end

  defp do_exec(fun) do
    try do
      fun.()
    rescue
      e -> { :error, Exception.message(e) }
    end
  end

end
