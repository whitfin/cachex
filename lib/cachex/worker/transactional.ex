defmodule Cachex.Worker.Transactional do
  @moduledoc false
  # This module defines the Transactional actions a worker can take. Functions
  # in this module are required to use Mnesia for row locking and replication.
  # As such these implementations are far slower than others, but provide a good
  # level of consistency across nodes.

  # add some aliases
  alias Cachex.Util
  alias Cachex.Worker

  @doc """
  Read back the key from Mnesia, wrapping inside a read locked transaction. If
  the key does not exist we check to see if there's a fallback function. If there
  is we call it and then set the value into the cache, before returning it to the
  user. Otherwise we simply return a nil value in an ok tuple.
  """
  def get(state, key, options) do
    fb_fun =
      options
      |> Util.get_opt_function(:fallback)

    Util.handle_transaction(fn ->
      val = case :mnesia.read(state.cache, key) do
        [{ _cache, ^key, touched, ttl, value }] ->
          case Util.has_expired?(touched, ttl) do
            true  -> Worker.del(state, key); :missing;
            false -> value
          end
        _unrecognised_val -> :missing
      end

      case val do
        :missing ->
          { status, new_value } =
            result =
              state
              |> Util.get_fallback(key, fb_fun)

          state
          |> Worker.set(key, new_value)

          case status do
            :ok -> { :missing, new_value }
            :loaded -> result
          end
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
  def set(state, key, value, options) do
    ttl =
      options
      |> Util.get_opt_number(:ttl)

    Util.handle_transaction(fn ->
      state
      |> Util.create_record(key, value, ttl)
      |> :mnesia.write
    end)
    |> (&(Util.create_truthy_result(&1 == { :ok, :ok }))).()
  end

  @doc """
  Updates a key in the cache to have a new value. This does not change the touch
  time or the TTL on the key. We return an ok/error tuple representing the state
  of the update request.
  """
  def update(state, key, value, _options) do
    state
    |> Worker.get_and_update(key, fn(_val) -> value end)
    |> (&(Util.create_truthy_result(elem(&1, 0) == :ok))).()
  end

  @doc """
  Removes a record from the cache using the provided key. We wrap this in a
  write lock in order to ensure no clashing writes occur at the same time.
  """
  def del(state, key, _options) do
    fn -> :mnesia.delete(state.cache, key, :write) end
    |> Util.handle_transaction()
    |> (&(Util.create_truthy_result(&1 == { :ok, :ok }))).()
  end

  @doc """
  Empties the cache entirely. We check the size of the cache beforehand using
  `size/1` in order to return the number of records which were removed.
  """
  def clear(state, _options) do
    eviction_count = case Worker.size(state) do
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
  def expire(state, key, expiration, _options) do
    Worker.get_and_update_raw(state, key, fn({ cache, ^key, _, _, value }) ->
      { cache, key, Util.now(), expiration, value }
    end)
    Util.ok(true)
  end

  @doc """
  Uses a select internally to fetch all the keys in the underlying Mnesia table.
  We use a select to pull only keys which have not expired.
  """
  def keys(state, _options) do
    Util.handle_transaction(fn ->
      :mnesia.dirty_select(state.cache, Util.retrieve_all_rows(:"$1"))
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
      (nil) -> initial + amount
      (val) -> val + amount
    end)
  end

  @doc """
  Refreshes the internal timestamp on the record to ensure that the TTL only takes
  place from this point forward. If the key does not exist, we return an error tuple.
  """
  def refresh(state, key, _options) do
    Worker.get_and_update_raw(state, key, fn({ cache, ^key, _, ttl, value }) ->
      { cache, key, Util.now(), ttl, value }
    end)
    Util.ok(true)
  end

  @doc """
  This is like `del/2` but it returns the last known value of the key as it
  existed in the cache upon deletion. We have to do a read/write combination
  when distributed, because there's no "take" equivalent in Mnesia, only ETS.
  """
  def take(state, key, _options) do
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
  Checks the remaining TTL on a provided key. We do this by retrieving the local
  record and pulling out the touched and ttl fields. In order to calculate the
  remaining time, we simply subtract the sum of these numbers from the current
  time in milliseconds. We return the remaining time to live in an ok tuple. If
  the key does not exist in the cache, we return an error tuple with a warning.
  """
  def ttl(state, key, _options) do
    Util.handle_transaction(fn ->
      case :mnesia.read(state.cache, key) do
        [{ _cache, ^key, touched, ttl, _value }] ->
          case Util.has_expired?(touched, ttl) do
            true  ->
              Worker.del(state, key)
              { :missing, nil }
            false ->
              case ttl do
                nil -> { :ok, nil }
                val -> { :ok, touched + val - Util.now() }
              end
          end
        _unrecognised_val ->
          { :missing, nil }
      end
    end)
  end

end
