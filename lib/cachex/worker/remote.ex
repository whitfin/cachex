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
    state.cache
    |> :mnesia.dirty_write(record)
    |> (&(Util.create_truthy_result(&1 == :ok))).()
  end

  @doc """
  Read back the key from Mnesia, using a dirty read for performance/replication.
  If the key does not exist we return a `nil` value. If the key has expired, we
  delete it from the cache using the `:purge` action as a notification.
  """
  def read(state, key) do
    case :mnesia.dirty_read(state.cache, key) do
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
  Updates a number of fields in a record inside the cache, by key. We delegate to
  the implementation in the Transactional Worker to avoid duplication.
  """
  defdelegate update(state, key, changes),
  to: Cachex.Worker.Transactional

  @doc """
  Removes a record from the cache using the provided key. Regardless of whether
  the key exists or not, we return a truthy value (to signify the record is not
  in the cache).
  """
  def delete(state, key) do
    state.cache
    |> :mnesia.dirty_delete(key)
    |> (&(Util.create_truthy_result(&1 == :ok))).()
  end

  @doc """
  Empties the cache entirely of keys. We delegate to the Transactional actions
  as the behaviour matches between implementations.
  """
  defdelegate clear(state, options),
  to: Cachex.Worker.Transactional

  @doc """
  Uses a select internally to fetch all the keys in the underlying Mnesia table.
  We use a fast select to determine that we only pull keys back which are not
  already expired.
  """
  def keys(state, _options) do
    state.cache
    |> :mnesia.dirty_select(Util.retrieve_all_rows(:"$1"))
    |> Util.ok
  end

  @doc """
  We delegate to the Transactional actions as this function requires both a
  get/set, and as such it's only safe to do via a transaction.
  """
  defdelegate incr(state, key, options),
  to: Cachex.Worker.Transactional

  @doc """
  This is like `del/2` but it returns the last known value of the key as it
  existed in the cache upon deletion. We delegate to the Transactional actions
  as this requires a potential get/del combination.
  """
  defdelegate take(state, key, options),
  to: Cachex.Worker.Transactional

end
