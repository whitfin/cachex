defmodule Cachex.Worker.Actions.Local do
  @moduledoc false
  # This module defines the Local actions a worker can take. Functions in this
  # module are focused around the sole use of ETS (although it can make use of
  # Mnesia as needed). This allows us to provid the fastest possible throughput
  # for a simple local, in-memory cache. Please note that when calling functions
  # from inside this module (internal functions), you should go through the
  # Actions parent module to avoid creating potentially messy internal dependency.

  # add some aliases
  alias Cachex.Util
  alias Cachex.Worker.Actions

  @doc """
  Simply do an ETS lookup on the given key. If the key does not exist we check
  to see if there's a fallback function. If there is we call it and then set the
  value into the cache ##TODO##, before returning it to the user. Otherwise we
  simply return a nil value in an ok tuple.
  """
  def get(state, key, fb_fun \\ nil) do
    val = case :ets.lookup(state.cache, key) do
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
  end

  @doc """
  Inserts a value directly into the ETS table, not caring if we overwrite a value
  or not. We use the parent implementation of creating a record for consistency,
  which provides us our TTL implementation. We transform the result of the insert
  into an ok/error tuple.
  """
  def set(state, key, value, ttl \\ nil) do
    new_record =
      state
      |> Util.create_record(key, value, ttl)

    state.cache
    |> :ets.insert(new_record)
    |> (&(&1 && Util.ok(true) || Util.error(false))).()
  end

  @doc """
  Increments a given key by a given amount. We do this using the internal ETS
  `update_counter/4` function. We allow for touching the record or keeping it
  persistent (for use cases such as rate limiting). If the record is missing, we
  insert a new one based on the passed values (but it has no TTL). We return the
  value after it has been incremented.
  """
  def incr(state, key, amount, initial_value, touched) do
    new_record =
      state
      |> Util.create_record(key, initial_value)

    body = case touched do
      :touched   -> [{ 3, Util.now() }, { 5, amount }]
      _untouched -> { 5, amount }
    end

    state.cache
    |> :ets.update_counter(key, body, new_record)
    |> Util.ok()
  end

  @doc """
  Removes a record from the cache using the provided key. Regardless of whether
  the key exists or not, we return a truthy value (to signify the record is not
  in the cache).
  """
  def del(state, key) do
    state.cache
    |> :ets.delete(key)
    |> Util.ok()
  end

  @doc """
  This is like `del/2` but it returns the last known value of the key as it
  existed in the cache upon deletion.
  """
  def take(state, key) do
    value = case :ets.take(state.cache, key) do
      [{ _cache, ^key, touched, ttl, value }] ->
        case Util.has_expired(touched, ttl) do
          true  -> nil
          false -> value
        end
      _unrecognised_val -> nil
    end

    Util.ok(value)
  end

  @doc """
  Empties the cache entirely, by calling `:ets.delete_all_objects/1`. We check
  the size of the cache beforehand using `size/1` in order to return the number
  of records which were removed.
  """
  def clear(state) do
    eviction_count = case Actions.size(state) do
      { :ok, size } -> size
      _other_value_ -> nil
    end

    state.cache
    |> :ets.delete_all_objects
    |> (&(&1 && { :ok, eviction_count })).()
  end

  @doc """
  Sets the expiration time on a given key based on the value passed in. We do this
  by dropping to the ETS layer and calling `:ets.update_element/4`. We provide
  the touch time as of now, as well as the new expiration. This will ensure that
  the key does not expire until `now() + expiration`. If the key is not found in
  the cache we short-circuit to avoid accidentally creating a record.
  """
  def expire(state, key, expiration) do
    if Actions.exists?(state, key) do
      state.cache
      |> :ets.update_element(key, [{ 3, Util.now() }, { 4, expiration }])
      |> (&({ :ok, &1 })).()
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
    case :ets.lookup(state.cache, key) do
      [{ _cache, ^key, touched, ttl, _value }] ->
        case ttl do
          nil -> { :ok, nil }
          val -> { :ok, touched + val - Util.now() }
        end
      _unrecognised_val ->
        { :error, "Key not found in cache"}
    end
  end

end
