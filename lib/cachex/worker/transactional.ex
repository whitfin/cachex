defmodule Cachex.Worker.Transactional do
  # ensure we use the actions interface
  @behaviour Cachex.Worker

  @moduledoc false
  # This module defines the Transactional actions a worker can take. Functions
  # in this module are required to use Mnesia for row locking and replication.
  # As such these implementations are far slower than others, but provide a good
  # level of consistency across nodes.

  # add some aliases
  alias Cachex.Util
  alias Cachex.Worker

  # define purge constants
  @purge_override [{ :via, { :purge } }, { :hook_result, { :ok, 1 } }]

  @doc """
  Writes a record into the cache, and returns a result signifying whether the
  write was successful or not.
  """
  def write(_state, record) do
    Util.handle_transaction(fn ->
      :mnesia.write(record) == :ok
    end)
  end

  @doc """
  Read back the key from Mnesia, wrapping inside a read locked transaction. If
  the key does not exist we return a `nil` value. If the key has expired, we delete
  it from the cache using the `:purge` action as a notification.
  """
  def read(state, key) do
    Util.handle_transaction(fn ->
      case :mnesia.read(state.cache, key) do
        [{ _cache, ^key, touched, ttl, _value } = record] ->
          case Util.has_expired?(state, touched, ttl) do
            true  -> Worker.del(state, key, @purge_override) && nil
            false -> record
          end
        _unrecognised_val ->
          nil
      end
    end, 1)
  end

  @doc """
  Updates a number of fields in a record inside the cache, by key. We do this all
  in one sweep using a reduction on the found record. Note that the position has
  to be offset -1 to line up with the ETS insertion (which is index 1 based).
  """
  def update(state, key, changes) do
    Worker.get_and_update_raw(state, key, fn(record) ->
      changes |> List.wrap |> Enum.reduce(record, fn({ position, value }, record) ->
        put_elem(record, position - 1, value)
      end)
    end)
    { :ok, true }
  end

  @doc """
  Removes a record from the cache using the provided key. We wrap this in a
  write lock in order to ensure no clashing writes occur at the same time.
  """
  def delete(state, key) do
    Util.handle_transaction(fn ->
      :mnesia.delete(state.cache, key, :write) == :ok
    end)
  end

  @doc """
  Empties the cache entirely. We check the size of the cache beforehand using
  `size/1` in order to return the number of records which were removed.
  """
  def clear(state, _options) do
    eviction_count = case Worker.size(state, notify: false) do
      { :ok, size } -> size
      _other_value_ -> nil
    end

    state.cache
    |> :mnesia.clear_table
    |> Util.handle_transaction(eviction_count)
  end

  @doc """
  Uses a select internally to fetch all the keys in the underlying Mnesia table.
  We use a select to pull only keys which have not expired.
  """
  def keys(state, _options) do
    Util.handle_transaction(fn ->
      :mnesia.select(state.cache, Util.retrieve_all_rows(:"$1"))
    end)
  end

  @doc """
  Increments a given key by a given amount. We do this by reusing the update
  semantics defined for all Worker. If the record is missing, we insert a new
  one based on the passed values (but it has no TTL). We return the value after
  it has been incremented.
  """
  def incr(state, key, options) do
    amount =
      options
      |> Util.get_opt_number(:amount, 1)

    initial =
      options
      |> Util.get_opt_number(:initial, 0)

    Worker.get_and_update(state, key, fn
      (val) when is_number(val) ->
        val + amount
      (nil) ->
        initial + amount
      (_na) ->
        Cachex.abort(state, :non_numeric_value)
    end, notify: false)
  end

  @doc """
  This is like `del/2` but it returns the last known value of the key as it
  existed in the cache upon deletion. We have to do a read/write combination
  when distributed, because there's no "take" equivalent in Mnesia, only ETS.
  """
  def take(state, key, _options) do
    Util.handle_transaction(fn ->
      value = case read(state, key) do
        { _cache, ^key, _touched, _ttl, value } ->
          { :ok, value }
        _unrecognised_val ->
          { :missing, nil }
      end

      if elem(value, 1) != nil do
        Worker.del(state, key, notify: false)
      end

      value
    end)
  end

end
