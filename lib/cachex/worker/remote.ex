defmodule Cachex.Worker.Remote do
  # ensure we use the actions interface
  @behaviour Cachex.Worker

  @moduledoc false
  # This module defines the Remote actions a worker can take. Functions in this
  # module are focused around the sole use of Mnesia in order to provide needed
  # replication. These calls do not handle row locking and as such they're a
  # middle ground (in terms of performance) between the Local actions and the
  # Transactional actions. Many functions in here delegate to the Transactional
  # actions due to consistency assurances.

  # add some aliases
  alias Cachex.Util
  alias Cachex.Worker

  # define purge constants
  @purge_override [{ :via, { :purge } }, { :hook_result, { :ok, 1 } }]

  @doc """
  Writes a record into the cache, and returns a result signifying whether the
  write was successful or not.
  """
  def write(state, record) do
    :mnesia.async_dirty(fn ->
      state.cache
      |> :mnesia.write(record, :write)
      |> (&(Util.create_truthy_result(&1 == :ok))).()
    end)
  end

  @doc """
  Read back the key from Mnesia, using a dirty read for performance/replication.
  If the key does not exist we return a `nil` value. If the key has expired, we
  delete it from the cache using the `:purge` action as a notification.
  """
  def read(state, key) do
    :mnesia.async_dirty(fn ->
      case :mnesia.read(state.cache, key) do
        [{ _cache, ^key, touched, ttl, _value } = record] ->
          if Util.has_expired?(state, touched, ttl) do
            Worker.del(state, key, @purge_override) && nil
          else
            record
          end
        _unrecognised_val ->
          nil
      end
    end)
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
  Removes a record from the cache using the provided key. Regardless of whether
  the key exists or not, we return a truthy value (to signify the record is not
  in the cache).
  """
  def delete(state, key) do
    :mnesia.async_dirty(fn ->
      state.cache
      |> :mnesia.delete(key, :write)
      |> (&(Util.create_truthy_result(&1 == :ok))).()
    end)
  end

  @doc """
  Empties the cache entirely. We check the size of the cache beforehand using
  `size/1` in order to return the number of records which were removed.
  """
  def clear(state, _options) do
    eviction_count = case Worker.size(state, notify: false) do
      { :ok, size } -> size
      _other_value_ -> 0
    end

    state.cache
    |> :mnesia.clear_table
    |> Util.handle_transaction(eviction_count)
  end

  @doc """
  Uses a select internally to fetch all the keys in the underlying Mnesia table.
  We use a fast select to determine that we only pull keys back which are not
  already expired.
  """
  def keys(state, _options) do
    :mnesia.async_dirty(fn ->
      state.cache
      |> :mnesia.select(Util.retrieve_all_rows(:key))
      |> Util.ok
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
