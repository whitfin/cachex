defmodule Cachex.Worker.Actions do
  alias Cachex.Util

  @doc """
  Basic key/value retrieval. Does a lookup on the key, and if the key exists we
  feed the value back to the user, otherwise we feed a nil back to the user.
  """
  def get(state, key, fb_fun \\ nil) do
    case :mnesia.dirty_read(state.cache, key) do
      [{ _cache, ^key, _touched, _ttl, value }] ->
        { :ok, value }
      _unrecognised_val ->
        case fb_fun do
          nil -> { :ok, nil }
          fun -> { :loaded, fun.() }
        end
    end
  end

  @doc """
  Grabs a list of keys for the user (the entire keyspace). This is pretty costly
  (as far as things go), so should be avoided except when debugging.
  """
  def keys(state) do
    { :ok, :mnesia.dirty_all_keys(state.cache) }
  end

  @doc """
  Basic key/value setting. Simply inserts the key into the table alongside the
  value. The user receives `true` as output, because all writes should succeed.
  """
  def set(state, key, value) do
    new_record =
      state
      |> create_record(key, value)

    :mnesia.dirty_write(state.cache, new_record)
    |> (&(&1 == :ok) && Util.ok(true) || Util.error(false)).()
  end

  @doc """
  Increments a value by a given amount, setting the value to an initial value if
  it does not already exist. The value returned is the value *after* increment.
  """
  def incr(state, key, amount, initial_value) do
    new_record =
      state
      |> create_record(key, initial_value)

    :ets.update_counter(state.cache, key, { 5, amount }, new_record) |> Util.ok
  end

  @doc """
  Decrements a value by a given amount, setting the value to an initial value if
  it does not already exist. The value returned is the value *after* decrement.
  """
  def decr(state, key, amount, initial_value),
  do: incr(state, key, amount * -1, initial_value)

  @doc """
  Increments a value by a given amount, setting the value to an initial value if
  it does not already exist. The value returned is the value *after* increment.
  """
  def t_incr(state, key, amount, initial_value) do
    new_record =
      state
      |> create_record(key, initial_value)

    :ets.update_counter(state.cache, key, [{ 3, Util.now() }, { 5, amount }], new_record) |> Util.ok
  end

  @doc """
  Decrements a value by a given amount, setting the value to an initial value if
  it does not already exist. The value returned is the value *after* decrement.
  """
  def t_decr(state, key, amount, initial_value),
  do: t_incr(state, key, amount * -1, initial_value)

  @doc """
  Removes a key/value pair from the cache.
  """
  def del(state, key) do
    { :ok, :mnesia.dirty_delete(state.cache, key) }
  end

  @doc """
  Removes a key/value pair from the cache, but returns the last known value of
  the key as it existed in the cache on removal.
  """
  def take(state, key) do
    value = case :mnesia.dirty_read(state.cache, key) do
      [{ _cache, ^key, _touched, _ttl, value }] -> value
      _unrecognised_val -> nil
    end

    if value != nil do
      :mnesia.dirty_delete(state.cache, key)
    end

    Util.ok(value)
  end

  @doc """
  Removes all values from the cache.
  """
  def clear(state) do
    eviction_count = case size(state) do
      { :ok, size } -> size
      _other_value_ -> nil
    end

    case :mnesia.clear_table(state.cache) do
      { :atomic, :ok } -> { :ok, eviction_count }
      { :aborted, reason } -> { :error, reason }
    end
  end

  @doc """
  Determines whether the cache is empty or not, returning a boolean representing
  the state.
  """
  def empty?(state) do
    case size(state) do
      { :ok, size } -> { :ok, size == 0 }
      _other_value_ -> { :ok, false }
    end
  end

  @doc """
  Determines whether a key exists in the cache. When the intention is to retrieve
  the value, it's faster to do a blind get and check for nil.
  """
  def exists?(state, key) do
    { :ok, :ets.member(state.cache, key) }
  end

  @doc """
  Refreshes the expiration on a given key based on the value passed in. We drop
  to ETS in order to do an in-place change rather than lock, pull, and update.
  """
  def expire(state, key, expiration) do
    if exists?(state, key) do
      :ets.update_element(state.cache, key, [{ 3, Util.now() }, { 4, expiration }])
      Util.ok(true)
    else
      Util.error("Key not found in cache")
    end
  end

  @doc """
  Refreshes the expiration on a given key to match the timestamp passed in. We
  drop to ETS in order to do an in-place change rather than lock, pull, and update.
  """
  def expire_at(state, key, timestamp) do
    expire(state, key, timestamp - Util.now())
  end

  @doc """
  Removes a set TTL from a given key.
  """
  def expire_at(state, key) do
    if exists?(state, key) do
      :ets.update_element(state.cache, key, [{ 4, nil }])
      Util.ok(true)
    else
      Util.error("Key not found in cache")
    end
  end

  @doc """
  Determines the current size of the cache, as returned by the info function.
  """
  def size(state) do
    { :ok, :mnesia.table_info(state.cache, :size) }
  end

  @doc """
  Returns the time remaining on a key before expiry. The value returned it in
  milliseconds. If the key has no expiration, nil is returned.
  """
  def ttl(state, key) do
    case :mnesia.dirty_read(state.cache, key) do
      [{ _cache, ^key, touched, ttl, _value }] ->
        case ttl do
          nil -> { :ok, nil }
          val -> { :ok, touched + val - Util.now() }
        end
      _unrecognised_val ->
        { :error, "Key not found in cache"}
    end
  end

  # Creates an input record based on a key, value and state. Uses the state to
  # determine the expiration from a default ttl, before passing the expiration
  # through to `create_record/4`.
  defp create_record(state, key, value) do
    create_record(state, key, value, state.default_ttl)
  end

  # Creates an input record based on a key, value and expiration. If the value
  # passed is nil, then we don't apply an expiration. Otherwise we add the value
  # to the current time (in milliseconds) and return a tuple for the table.
  defp create_record(state, key, value, expiration) do
    exp = case expiration do
      nil -> state.default_ttl
      val -> val
    end
    { state.cache, key, Util.now(), exp, value }
  end

end
