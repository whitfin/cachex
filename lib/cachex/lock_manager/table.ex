defmodule Cachex.LockManager.Table do
  @lock_table :cachex_lock_table

  def start_link do
    Eternal.start_link(
      @lock_table,
      [ read_concurrency: true, write_concurrency: true ],
      [ quiet: true ]
    )
  end

  def lock(cache, keys) do
    writes =
      keys
      |> List.wrap
      |> Enum.map(&({ { cache, &1 }, self() }))

    :ets.insert(@lock_table, writes)
  end

  def transaction(cache, keys, fun) when is_function(fun, 0) do
    true = lock(cache, keys)
    v = fun.()
    true = unlock(cache, keys)
    v
  end

  def unlock(cache, keys) do
    keys
    |> List.wrap
    |> Enum.map(&:ets.delete(@lock_table, { cache, &1 }))
    true
  end

  def writable?(cache, key) do
    case :ets.lookup(@lock_table, { cache, key }) do
      [{ _key, proc }] ->
        proc == self()
      _else ->
        true
    end
  end

end
