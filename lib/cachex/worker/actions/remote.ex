defmodule Cachex.Worker.Actions.Remote do
  @moduledoc false
  # This module defines the Remote actions a worker can take. Functions in this
  # module are focused around the sole use of Mnesia in order to provide needed
  # replication. These calls do not handle row locking and as such they're a
  # middle ground (in terms of performance) between the Local actions and the
  # Transactional actions. Many functions in here delegate to the Transactional
  # actions due to consistency assurances.

  # add some aliases
  alias Cachex.Util
  alias Cachex.Worker.Actions

  @doc """
  Simply do an Mnesia dirty read on the given key. If the key does not exist we
  check to see if there's a fallback function. If there is we call it and then
  set the value into the cache before returning it to the user. Otherwise we
  simply return a nil value in an ok tuple.
  """
  def get(state, key, fb_fun \\ nil) do
    val = case :mnesia.dirty_read(state.cache, key) do
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
  Inserts a value into the Mnesia tables, without caring about overwrites. We
  transform the result into an ok/error tuple to keep consistency in the API.
  """
  def set(state, key, value, ttl \\ nil) do
    state
    |> Util.create_record(key, value, ttl)
    |> :mnesia.dirty_write
    |> (&(&1 == :ok) && Util.ok(true) || Util.ok(false)).()
  end

  @doc """
  We delegate to the Transactional actions as this function requires both a
  get/set, and as such it's only safe to do via a transaction.
  """
  defdelegate incr(state, key, amount, initial_value),
  to: Cachex.Worker.Actions.Transactional

  @doc """
  Removes a record from the cache using the provided key. Regardless of whether
  the key exists or not, we return a truthy value (to signify the record is not
  in the cache).
  """
  def del(state, key) do
    state.cache
    |> :mnesia.dirty_delete(key)
    |> Util.ok()
  end

  @doc """
  This is like `del/2` but it returns the last known value of the key as it
  existed in the cache upon deletion. We delegate to the Transactional actions
  as this requires a potential get/del combination.
  """
  defdelegate take(state, key),
  to: Cachex.Worker.Actions.Transactional

  @doc """
  Empties the cache entirely of keys. We delegate to the Transactional actions
  as the behaviour matches between implementations.
  """
  defdelegate clear(state),
  to: Cachex.Worker.Actions.Transactional

  @doc """
  Sets the expiration time on a given key based on the value passed in. We pass
  this through to the Transactional actions as we require a get/set combination.
  """
  defdelegate expire(state, key, expiration),
  to: Cachex.Worker.Actions.Transactional

  @doc """
  Refreshes the internal timestamp on the record to ensure that the TTL only takes
  place from this point forward. We pass this through to the Transactional actions
  as we require a get/set combination.
  """
  defdelegate refresh(state, key),
  to: Cachex.Worker.Actions.Transactional

  @doc """
  Checks the remaining TTL on a provided key. We do this by retrieving the local
  record and pulling out the touched and ttl fields. In order to calculate the
  remaining time, we simply subtract the sum of these numbers from the current
  time in milliseconds. We return the remaining time to live in an ok tuple. If
  the key does not exist in the cache, we return an error tuple with a warning.
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

end
