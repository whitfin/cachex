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

  @doc """
  Simply do an ETS lookup on the given key. If the key does not exist we check
  to see if there's a fallback function. If there is we call it and then set the
  value into the cache, before returning it to the user. Otherwise we
  simply return a nil value in an ok tuple.
  """
  def get(state, key, options) do
    fb_fun =
      options
      |> Util.get_opt_function(:fallback)

    val = case :ets.lookup(state.cache, key) do
      [{ _cache, ^key, touched, ttl, value }] ->
        case Util.has_expired?(touched, ttl) do
          true  -> Worker.del(state, key); :missing;
          false -> value
        end
      _unrecognised_val -> :missing
    end

    case val do
      :missing ->
        case Util.get_fallback(state, key, fb_fun) do
          { :ok, new_value } ->
            { :missing, new_value }
          { :loaded, new_value } = result ->
            Worker.set(state, key, new_value)
            result
        end
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
  def set(state, key, value, options) do
    ttl =
      options
      |> Util.get_opt_number(:ttl)

    new_record =
      state
      |> Util.create_record(key, value, ttl)

    state.cache
    |> :ets.insert(new_record)
    |> (&(Util.create_truthy_result/1)).()
  end

  @doc """
  Updates a value directly in the cache. We directly update the value, without
  retrieving the value beforehand. Any TTL is left as-is as well as the touch
  time. We transform the result of the insert into an ok/error tuple.
  """
  def update(state, key, value, _options) do
    state.cache
    |> :ets.update_element(key, { 5, value })
    |> (&(Util.create_truthy_result/1)).()
  end

  @doc """
  Removes a record from the cache using the provided key. Regardless of whether
  the key exists or not, we return a truthy value (to signify the record is not
  in the cache any longer).
  """
  def del(state, key, _options) do
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
    eviction_count = case Worker.size(state) do
      { :ok, size } -> size
      _other_value_ -> nil
    end

    state.cache
    |> :ets.delete_all_objects
    |> (&(&1 && Util.ok(eviction_count) || Util.error(0))).()
  end

  @doc """
  Sets the expiration time on a given key based on the value passed in. We do this
  by dropping to the ETS layer and calling `:ets.update_element/4`. We provide
  the touch time as of now, as well as the new expiration. This will ensure that
  the key does not expire until `now() + expiration`. If the key is not found in
  the cache we short-circuit to avoid accidentally creating a record.
  """
  def expire(state, key, expiration, _options) do
    state.cache
    |> :ets.update_element(key, [{ 3, Util.now() }, { 4, expiration }])
    |> (&(Util.create_truthy_result/1)).()
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

    state.cache
    |> :ets.update_counter(key, { 5, amount }, new_record)
    |> Util.ok()
  end

  @doc """
  Refreshes the internal timestamp on the record to ensure that the TTL only takes
  place from this point forward. This is useful for epheremal caches. We return an
  error if the key does not exist in the cache.
  """
  def refresh(state, key, _options) do
    state.cache
    |> :ets.update_element(key, { 3, Util.now() })
    |> (&(Util.create_truthy_result/1)).()
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
            Worker.del(state, key)
            { :missing, nil }
          false ->
            { :ok, value }
        end
      _unrecognised_val ->
        { :missing, nil }
    end
  end

  @doc """
  Checks the remaining TTL on a provided key. We do this by retrieving the local
  record and pulling out the touched and ttl fields. In order to calculate the
  remaining time, we simply subtract the sum of these numbers from the current
  time in milliseconds. We return the remaining time to live in an ok tuple. If
  the key does not exist in the cache, we return an error tuple with a warning.
  """
  def ttl(state, key, _options) do
    case :ets.lookup(state.cache, key) do
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
  end

end
