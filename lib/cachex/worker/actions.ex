defmodule Cachex.Worker.Actions do
  # use Macros
  use Cachex.Macros.Actions

  @moduledoc false
  # This module defines the actions a worker can take. The reason for splitting
  # this out is so that it's easier to use internal functions (for example, we
  # might wish to re-use `size/1`). When defined in the Worker module, it was too
  # messy, and it's not possible to call GenServer functions from within. This
  # module acts as an interface to different implementations. Currently we only
  # have local storage via ETS, but it's totally possible to plug in a remote
  # implementation to replicate across nodes (I have one but it's still not quite
  # finished). The module being built in this way provides a clear migration path
  # to this in future, without having to rewrite and restructure the entire thing.

  # import worker for convenience
  import Cachex.Worker

  # add some aliases
  alias Cachex.Janitor
  alias Cachex.Util

  @doc """
  Basic key/value retrieval. Does a lookup on the key, and if the key exists we
  feed the value back to the user, otherwise we feed a nil back to the user. This
  function delegates to the actions modules to allow for optimizations.
  """
  def get(state, key, fb_fun \\ nil)
  defaction get(state, key, fb_fun)

  @doc """
  Provides a transactional interface to updating a value, by passing the value
  back into a provided function and storing the result. Touch time is updated
  but ttl is persisted, as this a convenient wrapper around setting a value.
  The return value is the value returned by the update function (i.e. the updated)
  state in the table.
  """
  def get_and_update(state, key, update_fun, fb_fun \\ nil)
  defaction get_and_update(state, key, update_fun, fb_fun) when is_function(update_fun) do
    result = get_and_update_raw(state, key, fn({ cache, ^key, touched, ttl, value }) ->
      { cache, key, touched, ttl, case value do
        nil ->
          state
          |> Util.get_fallback(key, fb_fun)
          |> update_fun.()
        val ->
          update_fun.(val)
      end }
    end)

    case result do
      { :ok, res } -> { :ok, elem(res, 4) }
      other_states -> other_states
    end
  end

  @doc """
  A raw interface for the update of a document in the table. This is a for use
  only by internal modules, as you can cause unintentional bugs with bad changes
  in this function. `get_and_update_raw/3` takes an update function which receives
  either the document or a faked out tuple. The new document returned is directly
  indexed into the table.
  """
  defaction get_and_update_raw(state, key, update_fun) when is_function(update_fun) do
    Util.handle_transaction(fn ->
      value = case :mnesia.read(state.cache, key) do
        [{ cache, ^key, touched, ttl, value }] ->
          case Util.has_expired(touched, ttl) do
            true ->
              :mnesia.delete(state.cache, key, :write)
              { cache, key, Util.now(), nil, nil }
            false ->
              { cache, key, touched, ttl, value }
          end
        _unrecognised_val ->
          { state.cache, key, Util.now(), nil, nil }
      end

      new_value = update_fun.(value)
      :mnesia.write(new_value)
      new_value
    end)
  end

  @doc """
  Delegate for setting a value, simply setting a value to a key with an optional
  ttl. This function delegates to the actions modules to allow for optimizations.
  """
  def set(state, key, value, ttl \\ nil)
  defaction set(state, key, value, ttl)

  @doc """
  Increments a value by a given amount, setting the value to an initial value if
  it does not already exist. The value returned is the value *after* increment.
  This function delegates to the actions modules to allow for optimizations.
  """
  defaction incr(state, key, amount, initial_value)

  @doc """
  Removes a key/value pair from the cache. This function delegates to the actions
  modules to allow for optimizations.
  """
  defaction del(state, key)

  @doc """
  Removes all values from the cache, this empties the entire backing table. This
  function delegates to the actions modules to allow for optimizations.
  """
  defaction clear(state)

  @doc """
  Similar to `size/1`, but ignores keys which may have expired. This is slower
  and requires extra computation, hence the name `length/1` to signal as such.
  """
  defaction count(state) do
    state.cache
    |> :ets.select_count(Util.retrieve_all_rows(true))
    |> Util.ok
  end

  @doc """
  Determines whether a key exists in the cache. When the intention is to retrieve
  the value, it's faster to do a blind get and check for nil. It's ok for us to
  drop to ETS for this at all times because of the speed (i.e. it's almost not
  possible for this to be inaccurate aside from network partitions).
  """
  defaction exists?(state, key) do
    { :ok, :ets.member(state.cache, key) }
  end

  @doc """
  Modifies the expiration on a given key based on the value passed in. This
  function delegates to the actions modules to allow for optimizations.
  """
  defaction expire(state, key, expiration) do
    case exists?(state, key) do
      { :ok, true } ->
        state.actions.expire(state, key, expiration)
      _other_value_ ->
        { :error, "Key not found in cache"}
    end
  end

  @doc """
  Sets a date for expiration of a given key. The date should be a timestamp in
  UTC milliseconds. We forward this action to the `expire/3` function to avoid
  duplicating the logic behind the expiration.
  """
  defaction expire_at(state, key, timestamp),
  do: expire(state, key, timestamp - Util.now())

  @doc """
  Retrieves a list of keys from the cache. This is surprisingly fast, because we
  use a funky selection, but all the same it should be used less frequently as
  the payload being copied and sent back over the server is potentially costly.
  """
  defaction keys(state) do
    state.cache
    |> :mnesia.dirty_select(Util.retrieve_all_rows(:"$1"))
    |> Util.ok
  end

  @doc """
  Removes a TTL from a given key (and is safe if a key does not already have a
  TTL provided). We pass this to `expire/3` to avoid duplicating the update logic.
  """
  defaction persist(state, key),
  do: expire(state, key, nil)

  @doc """
  Purges all expired keys based on their current TTL values. We return the number
  of deleted records as an ok tuple.
  """
  defaction purge(state) do
    Janitor.purge_records(state.cache)
  end

  @doc """
  Refreshes the TTL on the given key - basically meaning the TTL starting expiring
  from this point onwards. This function delegates to the actions modules to allow
  for optimizations.
  """
  defaction refresh(state, key) do
    case exists?(state, key) do
      { :ok, true } ->
        state.actions.refresh(state, key)
      _other_value_ ->
        { :error, "Key not found in cache"}
    end
  end

  @doc """
  Determines the current size of the cache, as returned by the info function. This
  is going to be accurate to the millisecond at the very worst, so we can safely
  provide this implementation for all actions.
  """
  defaction size(state) do
    state.cache
    |> :mnesia.table_info(:size)
    |> Util.ok
  end

  @doc """
  Removes a key/value pair from the cache, but returns the last known value of
  the key as it existed in the cache on removal. This function delegates to the
  actions modules to allow for optimizations.
  """
  defaction take(state, key)

  @doc """
  Returns the time remaining on a key before expiry. The value returned is in
  milliseconds. If the key has no expiration, nil is returned. This function
  delegates to the actions modules to allow for optimizations.
  """
  defaction ttl(state, key)

end
