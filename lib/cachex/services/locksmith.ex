defmodule Cachex.Services.Locksmith do
  @moduledoc false
  # Locking service in charge of table transactions.
  #
  # This module acts as a global lock table against all cache. This is due to the
  # fact that ETS tables are fairly expensive to construct if they're only going
  # to store a few keys.
  #
  # Due to this we have a single global table in charge of locks, and we tag just
  # the key in the table with the name of the cache it's associated with. This
  # keyspace will typically be very small, so there should be almost no impact to
  # operating in this way (except that we only have a single ETS table rather than
  # a potentially large N).
  #
  # It should be noted that the behaviour in this module could easily live as a
  # GenServer if it weren't for the speedup gained when using ETS. When using an
  # ETS table, checking for a lock is typically 0.3-0.5µs/op whereas a call to a
  # server process is roughly 10x this (due to the process interactions).
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
  @spec lock(Cachex.t(), [any]) :: boolean
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
  @spec locked(Cachex.t()) :: [any]
  def locked(cache(name: name)),
    do: :ets.select(@table_name, [{{{name, :"$1"}, :_}, [], [:"$1"]}])

  @doc """
  Determines if a key is able to be written to by the current process.

  For a key to be writeable, it must either have no lock or be locked by the
  calling process.
  """
  @spec locked?(Cachex.t(), [any]) :: true | false
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

  If the process is not already in a transactional context, the required keys
  will be locked until the provided function has finished executing.

  If the process is already in a transactional context, the enclosing
  transaction must already hold a lock on every requested key; the function is
  then executed immediately. If any requested key is not already locked, a
  `Cachex.Error` is raised, as executing against unlocked keys inside a
  transaction is almost certainly a logic error.

  This is mainly shorthand to avoid having to handle row locking explicitly.
  """
  @spec transaction(Cachex.t(), [any], (-> any)) :: any
  def transaction(cache() = cache, keys, fun) when is_list(keys) do
    case Process.get(:cachex_transaction, false) do
      false ->
        Queue.transaction(cache, keys, fun)

      locked ->
        # Already inside a transaction; the enclosing transaction must already
        # hold a lock on every key we're asking for. If it doesn't, the caller
        # is executing against keys with no locking in place, which is almost
        # certainly a logic error, so we raise rather than silently proceed.
        case keys -- locked do
          [] ->
            fun.()

          _missing ->
            raise Cachex.Error,
              message: "Nested transaction requested keys not locked by the enclosing transaction"
        end
    end
  end

  @doc """
  Determines if the current process is in transactional context.
  """
  @spec transaction? :: boolean
  def transaction?,
    do: Process.get(:cachex_transaction, false) != false

  @doc """
  Flags this process as running in a transaction.

  The process dictionary stores the list of keys currently locked by the
  transaction (empty when no specific keys are held), which allows nested
  transactions to verify that they operate against already-locked keys.
  """
  @spec start_transaction :: no_return
  def start_transaction,
    do: Process.put(:cachex_transaction, [])

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
  @spec unlock(Cachex.t(), [any]) :: true
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
  @spec write(Cachex.t(), any, (-> any)) :: any
  def write(cache(transactions: false), _keys, fun),
    do: fun.()

  def write(cache() = cache, keys, fun) do
    case transaction?() or !locked?(cache, keys) do
      true -> fun.()
      false -> Queue.execute(cache, fun)
    end
  end
end
