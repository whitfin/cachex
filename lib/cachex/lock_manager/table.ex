defmodule Cachex.LockManager.Table do
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

  # our constant lock table
  @lock_table :cachex_lock_table

  @doc """
  Starts an Eternal ETS table to act as a global lock table.

  We start the table with no logging to make sure we don't spam a developer's
  log output. This may be configurable in future, but this table will likely
  never cause an issue in the first place (as it handles only basic interactions).
  """
  def start_link do
    Eternal.start_link(
      @lock_table,
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
  @spec lock(atom, [ any ]) :: true
  def lock(cache, keys) do
    t_proc = self()

    writes =
      keys
      |> List.wrap
      |> Enum.map(&({ { cache, &1 }, t_proc }))

    :ets.insert(@lock_table, writes)
  end

  @doc """
  Carries out a cache transaction.

  This will lock the required keys before executing the provided function. Once
  the function has completed, all locks will be removed. This is just a shorthand
  function to avoid having to handle row locking explicitly.
  """
  @spec transaction(atom, [ any ], ( -> any)) :: any
  def transaction(cache, keys, fun) do
    true = lock(cache, keys)
    v = fun.()
    true = unlock(cache, keys)
    v
  end

  @doc """
  Unlocks a list of keys against a given cache in the table.

  There's currently no way to batch delete items in ETS beyond a select_delete,
  so we have to simply iterate over the locks and remove them sequentially. This
  is a little less desirable, but needs must.
  """
  @spec unlock(atom, [ any ]) :: true
  def unlock(cache, keys) do
    keys
    |> List.wrap
    |> Enum.each(&:ets.delete(@lock_table, { cache, &1 }))
    true
  end

  @doc """
  Checks if a given key in the cache is writeable.

  For a key to be writeable, it must either have no lock, or be locked by the
  calling process.
  """
  @spec writable?(atom, any) :: true | false
  def writable?(cache, key) do
    case :ets.lookup(@lock_table, { cache, key }) do
      [{ _key, proc }] ->
        proc == self()
      _else ->
        true
    end
  end

end
