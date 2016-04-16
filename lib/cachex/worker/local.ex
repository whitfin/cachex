defmodule Cachex.Worker.Local do
  # ensure we use the actions interface
  @behaviour Cachex.Worker

  @moduledoc false
  # This module defines the Local actions a worker can take. Functions in this
  # module are focused around the sole use of ETS (although it can make use of
  # Mnesia as needed). This allows us to provid the fastest possible throughput
  # for a simple local, in-memory cache. Please note that when calling functions
  # from inside this module (internal functions), you should go through the
  # Worker parent module to avoid creating potentially messy internal dependency.

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
    state.cache
    |> :ets.insert(record)
    |> (&(Util.create_truthy_result/1)).()
  end

  @doc """
  Read back the key from ETS, by doing a raw lookup on the key for performance.
  If the key does not exist we return a `nil` value. If the key has expired, we
  delete it from the cache using the `:purge` action as a notification.
  """
  def read(state, key) do
    case :ets.lookup(state.cache, key) do
      [{ _cache, ^key, touched, ttl, _value } = record] ->
        case Util.has_expired?(touched, ttl) do
          true  -> Worker.del(state, key, @purge_override) && nil
          false -> record
        end
      _unrecognised_val ->
        nil
    end
  end

  @doc """
  Updates a number of fields in a record inside the cache, by key. We do this all
  in one sweep using the internal ETS update mechanisms.
  """
  def update(state, key, changes) do
    state.cache
    |> :ets.update_element(key, List.wrap(changes))
    |> (&(Util.create_truthy_result/1)).()
  end

  @doc """
  Removes a record from the cache using the provided key. Regardless of whether
  the key exists or not, we return a truthy value (to signify the record is not
  in the cache any longer).
  """
  def delete(state, key) do
    state.cache
    |> :ets.delete(key)
    |> Util.ok
  end

  @doc """
  Empties the cache entirely, by calling `:ets.delete_all_objects/1`. We check
  the size of the cache beforehand using `size/1` in order to return the number
  of records which were removed.
  """
  def clear(state, _options) do
    eviction_count = case Worker.size(state, notify: false) do
      { :ok, size } -> size
      _other_value_ -> nil
    end

    state.cache
    |> :ets.delete_all_objects
    |> (&(&1 && Util.ok(eviction_count) || Util.error(0))).()
  end

  @doc """
  Uses a select internally to fetch all the keys in the underlying Mnesia table.
  We use a fast select to determine that we only pull keys back which are not
  already expired.
  """
  def keys(state, _options) do
    state.cache
    |> :ets.select(Util.retrieve_all_rows(:"$1"))
    |> Util.ok
  end

  @doc """
  Increments a given key by a given amount. We do this using the internal ETS
  `update_counter/4` function. We allow for touching the record or keeping it
  persistent (for use cases such as rate limiting). If the record is missing, we
  insert a new one based on the passed values (but it has no TTL). We return the
  value after it has been incremented.
  """
  def incr(state, key, options) do
    amount =
      options
      |> Util.get_opt_number(:amount, 1)

    initial =
      options
      |> Util.get_opt_number(:initial, 0)

    new_record =
      state
      |> Util.create_record(key, initial)

    exists_key =
      state
      |> Worker.exists?(key, notify: false)

    new_value =
      state.cache
      |> :ets.update_counter(key, { 5, amount }, new_record)

    case exists_key do
      { :ok, true } ->
        { :ok, new_value }
      { :ok, false } ->
        { :missing, new_value }
    end
  end

  @doc """
  This is like `del/2` but it returns the last known value of the key as it
  existed in the cache upon deletion.
  """
  def take(state, key, _options) do
    case :ets.take(state.cache, key) do
      [{ _cache, ^key, touched, ttl, value }] ->
        case Util.has_expired?(touched, ttl) do
          true  ->
            { :missing, nil }
          false ->
            { :ok, value }
        end
      _unrecognised_val ->
        { :missing, nil }
    end
  end

end
