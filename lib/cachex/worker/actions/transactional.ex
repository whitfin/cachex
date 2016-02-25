defmodule Cachex.Worker.Actions.Transactional do
  @moduledoc false
  # This module defines the Transactional actions a worker can take. Functions
  # in this module are required to use Mnesia for row locking and replication.
  # As such these implementations are far slower than others, but provide a good
  # level of consistency across nodes.

  # add some aliases
  alias Cachex.Util
  alias Cachex.Worker.Actions

  @doc """
  Read back the key from Mnesia, wrapping inside a read locked transaction. If
  the key does not exist we check to see if there's a fallback function. If there
  is we call it and then set the value into the cache, before returning it to the
  user. Otherwise we simply return a nil value in an ok tuple.
  """
  def get(state, key, fb_fun \\ nil) do
    Util.handle_transaction(fn ->
      val = case :mnesia.read(state.cache, key) do
        [{ _cache, ^key, touched, ttl, value }] ->
          case Util.has_expired(touched, ttl) do
            true  -> Actions.del(state, key); nil;
            false -> value
          end
        _unrecognised_val -> nil
      end

      case val do
        nil ->
          new_value =
            state
            |> Util.get_fallback(key, fb_fun)

          Actions.set(state, key, new_value)

          { :loaded, new_value }
        val ->
          { :ok, val }
      end
    end)
  end

  @doc """
  Inserts a value directly into Mnesia not caring if we overwrite a value or not.
  We use the parent implementation of creating a record for consistency, which
  provides us our TTL implementation. We transform the result of the insert into
  an ok/error tuple.
  """
  def set(state, key, value, ttl \\ nil) do
    Util.handle_transaction(fn ->
      state
      |> Util.create_record(key, value, ttl)
      |> :mnesia.write
    end)
    |> (&(&1 == { :ok, :ok }) && Util.ok(true) || Util.error(false)).()
  end

  @doc """
  Increments a given key by a given amount. We do this by reusing the update
  semantics defined for all Actions. If the record is missing, we insert a new
  one based on the passed values (but it has no TTL). We return the value after
  it has been incremented. This method handles the touched increments.
  """
  def incr(state, key, amount, initial_value, :touched) do
    Actions.get_and_update_raw(state, key, fn
      ({ cache, key, _touched, ttl, nil }) ->
        { cache, key, Util.now(), ttl, initial_value + amount }
      ({ cache, key, _touched, ttl, val }) ->
        { cache, key, Util.now(), ttl, val + amount }
    end)
  end

  @doc """
  Similar to the other incr function, except this does not touch the value - it
  modifies in place to keep the touched time the same.
  """
  def incr(state, key, amount, initial_value, _untouched) do
    Actions.get_and_update(state, key, fn
      (nil) -> initial_value + amount
      (val) -> val + amount
    end)
  end

  @doc """
  Removes a record from the cache using the provided key. We wrap this in a
  write lock in order to ensure no clashing writes occur at the same time.
  """
  def del(state, key) do
    Util.handle_transaction(fn ->
      :mnesia.delete(state.cache, key, :write)
    end)
  end

  @doc """
  This is like `del/2` but it returns the last known value of the key as it
  existed in the cache upon deletion. We have to do a read/write combination
  when distributed, because there's no "take" equivalent in Mnesia, only ETS.
  """
  def take(state, key) do
    Util.handle_transaction(fn ->
      value = case :mnesia.read(state.cache, key) do
        [{ _cache, ^key, _touched, _ttl, value }] -> value
        _unrecognised_val -> nil
      end

      if value != nil do
        :mnesia.delete(state.cache, key, :write)
      end

      value
    end)
  end

  @doc """
  Empties the cache entirely. We check the size of the cache beforehand using
  `size/1` in order to return the number of records which were removed.
  """
  def clear(state) do
    eviction_count = case Actions.size(state) do
      { :ok, size } -> size
      _other_value_ -> nil
    end

    state.cache
    |> :mnesia.clear_table
    |> Util.handle_transaction(eviction_count)
  end

  @doc """
  Sets the expiration time on a given key based on the value passed in. We first
  check locally to see if the key actually exists, returning an error if it doesn't.
  This allows us to then reuse the update semantics to modify the expiration.
  """
  def expire(state, key, expiration) do
    if Actions.exists?(state, key) do
      Actions.get_and_update_raw(state, key, fn({ cache, ^key, _, _, value }) ->
        { cache, key, Util.now(), expiration, value }
      end)
      { :ok, true }
    else
      { :error, "Key not found in cache"}
    end
  end

  @doc """
  Checks the remaining TTL on a provided key. We do this by retrieving the local
  record and pulling out the touched and ttl fields. In order to calculate the
  remaining time, we simply subtract the sum of these numbers from the current
  time in milliseconds. We return the remaining time to live in an ok tuple. If
  the key does not exist in the cache, we return an error tuple with a warning.
  """
  def ttl(state, key) do
    Util.handle_transaction(fn ->
      case :mnesia.read(state.cache, key) do
        [{ _cache, ^key, touched, ttl, _value }] ->
          case ttl do
            nil -> { :ok, nil }
            val -> { :ok, touched + val - Util.now() }
          end
        _unrecognised_val ->
          { :error, "Key not found in cache"}
      end
    end)
  end

end
