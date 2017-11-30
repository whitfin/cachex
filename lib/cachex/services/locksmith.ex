defmodule Cachex.Services.Locksmith do
  @moduledoc false
  # This module controls the ETS table backing the LockManager. It should be noted
  # that this table acts as a global lock table against all caches. This is due
  # to the desire that an ETS table is a fairly expensive construct to store only
  # a few keys. Because of this we have a global table and just tag the record
  # in the table with the namespace of the cache it was written by. This table
  # will typically be very small (as locks are cleaned up as they go). It should
  # also be noted that this behaviour could easily live in a GenServer were it
  # not for the speedup when using ETS. When using an ETS table this check is
  # typically 0.3-0.5µs/op whereas a GenServer is roughly 10x this.
  import Cachex.Spec

  # our constant lock table
  @table_name :cachex_locksmith

  @doc """
  Starts an Eternal ETS table to act as a global lock table.

  We start the table with no logging to make sure we don't spam a developer's
  log output. This may be configurable in future, but this table will likely
  never cause an issue in the first place (as it handles only basic interactions).
  """
  @spec start_link :: GenServer.on_start
  def start_link do
    Eternal.start_link(
      @table_name,
      [ read_concurrency: true, write_concurrency: true ],
      [ quiet: true ]
    )
  end

  @doc """
  Locks a list of keys against a given cache in the table.

  We format the keys into a list of writes to optimize the interactions with ETS,
  rather than just repeatedly calling ETS with insertion. This also has the benefit
  of ensuring that all keys are locked at the same time.
  """
  @spec lock(Spec.cache, [ any ]) :: true
  def lock(cache(name: name), keys) do
    t_proc = self()

    writes =
      keys
      |> List.wrap
      |> Enum.map(&({ { name, &1 }, t_proc }))

    :ets.insert_new(@table_name, writes)
  end

  @doc """
  Returns the list of locked keys for a cache.
  """
  @spec locked(Spec.cache) :: [ any ]
  def locked(cache(name: name)),
    do: :ets.select(@table_name, [ { { { name, :"$1" }, :_ }, [], [ :"$1" ] } ])

  @doc """
  Carries out a cache transaction.

  This will lock the required keys before executing the provided function. Once
  the function has completed, all locks will be removed. This is just a shorthand
  function to avoid having to handle row locking explicitly.
  """
  @spec transaction(Spec.cache, [ any ], ( -> any)) :: any
  def transaction(cache(name: name), keys, fun) do
    case transaction?() do
      true  -> fun.()
      false -> GenServer.call(name(name, :locksmith), { :transaction, keys, fun }, :infinity)
    end
  end

  @doc """
  Detects if the current process is in transactional context.
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
  Unlocks a list of keys against a given cache in the table.

  There's currently no way to batch delete items in ETS beyond a select_delete,
  so we have to simply iterate over the locks and remove them sequentially. This
  is a little less desirable, but needs must.
  """
  @spec unlock(Spec.cache, [ any ]) :: true
  def unlock(cache(name: name), keys) do
    keys
    |> List.wrap
    |> Enum.all?(&:ets.delete(@table_name, { name, &1 }))
  end

  @doc """
  Checks if a given key in the cache is writeable.

  For a key to be writeable, it must either have no lock, or be locked by the
  calling process.
  """
  @spec writable?(Spec.cache, any) :: true | false
  def writable?(cache(name: name), key) do
    case :ets.lookup(@table_name, { name, key }) do
      [{ _key, proc }] ->
        proc == self()
      _else ->
        true
    end
  end

  @doc """
  Performs a write against the given key inside the table.

  If the key is locked, the write is queued inside the lock server to ensure that
  we execute consistently.
  """
  @spec write(Spec.cache, any, ( -> any)) :: any
  def write(cache(transactional: false), _key, fun),
    do: fun.()
  def write(cache(name: name) = cache, key, fun) do
    case transaction?() or writable?(cache, key) do
      true  -> fun.()
      false -> GenServer.call(name(name, :locksmith), { :exec, fun }, :infinity)
    end
  end
end
