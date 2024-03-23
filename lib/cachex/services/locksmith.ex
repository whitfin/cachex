defmodule Cachex.Services.Locksmith do
  @moduledoc """
  Locking service in charge of table transactions.

  This module acts as a global lock table against all cache. This is due to the
  fact that ETS tables are fairly expensive to construct if they're only going
  to store a few keys.

  Due to this we have a single global table in charge of locks, and we tag just
  the key in the table with the name of the cache it's associated with. This
  keyspace will typically be very small, so there should be almost no impact to
  operating in this way (except that we only have a single ETS table rather than
  a potentially large N).

  It should be noted that the behaviour in this module could easily live as a
  GenServer if it weren't for the speedup gained when using ETS. When using an
  ETS table, checking for a lock is typically 0.3-0.5µs/op whereas a call to a
  server process is roughly 10x this (due to the process interactions).
  """
  alias Cachex.Services.Locksmith.Queue

  # we need records
  import Cachex.Spec

  # our global lock table name
  @table_name :cachex_locksmith

  @doc """
  Starts the backing services required by the Locksmith.

  At this point this will start the backing ETS table required by the locking
  logic inside the Locksmith. This is started with concurrency enabled and
  logging disabled to avoid spamming log output.

  This may become configurable in future, but this table will likelyn never
  cause issues in the first place (as it only handles very basic operations).
  """
  @spec start_link :: GenServer.on_start()
  def start_link do
    Eternal.start_link(
      @table_name,
      [read_concurrency: true, write_concurrency: true],
      quiet: true
    )
  end

  @doc """
  Locks a number of keys for a cache.

  This function can handle multiple keys to lock together atomically. The
  returned boolean will signal if the lock was successful. A lock can fail
  if one of the provided keys is already locked.
  """
  @spec lock(Cachex.Spec.cache(), [any]) :: boolean
  def lock(cache(name: name), keys) do
    t_proc = self()

    writes =
      keys
      |> List.wrap()
      |> Enum.map(&{{name, &1}, t_proc})

    :ets.insert_new(@table_name, writes)
  end

  @doc """
  Retrieves a list of locked keys for a cache.

  This uses some ETS matching voodoo to pull back the locked keys. They
  won't be returned in any specific order, so don't rely on it.
  """
  @spec locked(Cachex.Spec.cache()) :: [any]
  def locked(cache(name: name)),
    do: :ets.select(@table_name, [{{{name, :"$1"}, :_}, [], [:"$1"]}])

  @doc """
  Determines if a key is able to be written to by the current process.

  For a key to be writeable, it must either have no lock or be locked by the
  calling process.
  """
  @spec locked?(Cachex.Spec.cache(), [any]) :: true | false
  def locked?(cache(name: name), keys) when is_list(keys) do
    Enum.any?(keys, fn key ->
      case :ets.lookup(@table_name, {name, key}) do
        [{_key, proc}] ->
          proc != self()

        _else ->
          false
      end
    end)
  end

  @doc """
  Executes a transaction against a cache table.

  If the process is already in a transactional context, the provided function
  will be executed immediately. Otherwise the required keys will be locked until
  the provided function has finished executing.

  This is mainly shorthand to avoid having to handle row locking explicitly.
  """
  @spec transaction(Cachex.Spec.cache(), [any], (-> any)) :: any
  def transaction(cache() = cache, keys, fun) when is_list(keys) do
    case transaction?() do
      true -> fun.()
      false -> Queue.transaction(cache, keys, fun)
    end
  end

  @doc """
  Determines if the current process is in transactional context.
  """
  @spec transaction? :: boolean
  def transaction?,
    do: Process.get(:cachex_transaction, false)

  @doc """
  Flags this process as running in a transaction.
  """
  @spec start_transaction :: no_return
  def start_transaction,
    do: Process.put(:cachex_transaction, true)

  @doc """
  Flags this process as not running in a transaction.
  """
  @spec stop_transaction :: no_return
  def stop_transaction,
    do: Process.put(:cachex_transaction, false)

  @doc """
  Unlocks a number of keys for a cache.

  There's currently no way to batch delete items in ETS beyond a select_delete,
  so we have to simply iterate over the locks and remove them sequentially. This
  is a little less desirable, but needs must.
  """
  # TODO: figure out how to remove atomically
  @spec unlock(Cachex.Spec.cache(), [any]) :: true
  def unlock(cache(name: name), keys) do
    keys
    |> List.wrap()
    |> Enum.all?(&:ets.delete(@table_name, {name, &1}))
  end

  @doc """
  Performs a write against the given key inside the table.

  If the key is locked, the write is queued inside the lock server
  to ensure that we execute consistently.

  This is a little hard to explain, but if the cache has not had any
  transactions executed against it we skip the lock check as any of
  our ETS writes are atomic and so do not require a lock.
  """
  @spec write(Cachex.Spec.cache(), any, (-> any)) :: any
  def write(cache(transactions: false), _keys, fun),
    do: fun.()

  def write(cache() = cache, keys, fun) do
    case transaction?() or !locked?(cache, keys) do
      true -> fun.()
      false -> Queue.execute(cache, fun)
    end
  end
end
