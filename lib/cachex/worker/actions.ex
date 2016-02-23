defmodule Cachex.Worker.Actions do
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

  # add a utils alias
  alias Cachex.Util

  @doc """
  Basic key/value retrieval. Does a lookup on the key, and if the key exists we
  feed the value back to the user, otherwise we feed a nil back to the user. This
  function delegates to the actions modules to allow for optimizations.
  """
  def get(state, key, fb_fun \\ nil),
  do: do_action(state, :get, [key, fb_fun])

  @doc """
  Provides a transactional interface to updating a value, by passing the value
  back into a provided function and storing the result. Touch time is updated
  but ttl is persisted, as this a convenient wrapper around setting a value.
  The return value is the value returned by the update function (i.e. the updated)
  state in the table.
  """
  def get_and_update(state, key, update_fun, fb_fun \\ nil)
  when is_function(update_fun) do
    get_and_update_raw(state, key, fn({ _cache, ^key, _touched, _ttl, value }) ->
      case value do
        nil ->
          state
          |> Util.get_fallback(key, fb_fun)
          |> update_fun.()
        val ->
          update_fun.(val)
      end
    end)
  end

  @doc """
  A raw interface for the update of a document in the table. This is a for use
  only by internal modules, as you can cause unintentional bugs with bad changes
  in this function. `get_and_update_raw/3` takes an update function which receives
  either the document or a faked out tuple. The new document returned is directly
  indexed into the table.
  """
  def get_and_update_raw(state, key, update_fun) when is_function(update_fun) do
    result = :mnesia.transaction(fn ->
      value = { _, _, _, ttl, _ } = case :mnesia.read(state.cache, key) do
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
      set(state, key, new_value, ttl)
      new_value
    end)

    Util.handle_transaction(result)
  end

  @doc """
  Delegate for setting a value, simply setting a value to a key with an optional
  ttl. This function delegates to the actions modules to allow for optimizations.
  """
  def set(state, key, value, ttl \\ nil),
  do: do_action(state, :set, [key, value, ttl])

  @doc """
  Increments a value by a given amount, setting the value to an initial value if
  it does not already exist. The value returned is the value *after* increment.
  This function delegates to the actions modules to allow for optimizations.
  """
  def incr(state, key, amount, initial_value, touched),
  do: do_action(state, :incr, [key, amount, initial_value, touched])

  @doc """
  Removes a key/value pair from the cache. This function delegates to the actions
  modules to allow for optimizations.
  """
  def del(state, key),
  do: do_action(state, :del, [key])

  @doc """
  Removes a key/value pair from the cache, but returns the last known value of
  the key as it existed in the cache on removal. This function delegates to the
  actions modules to allow for optimizations.
  """
  def take(state, key),
  do: do_action(state, :take, [key])

  @doc """
  Removes all values from the cache, this empties the entire backing table. This
  function delegates to the actions modules to allow for optimizations.
  """
  def clear(state),
  do: do_action(state, :clear)

  @doc """
  Determines whether a key exists in the cache. When the intention is to retrieve
  the value, it's faster to do a blind get and check for nil. It's ok for us to
  drop to ETS for this at all times because of the speed (i.e. it's almost not
  possible for this to be inaccurate aside from network partitions).
  """
  def exists?(state, key) do
    { :ok, :ets.member(state.cache, key) }
  end

  @doc """
  Modifies the expiration on a given key based on the value passed in. This
  function delegates to the actions modules to allow for optimizations.
  """
  def expire(state, key, expiration),
  do: do_action(state, :expire, [key, expiration])

  @doc """
  Sets a date for expiration of a given key. The date should be a timestamp in
  UTC milliseconds. We forward this action to the `expire/3` function to avoid
  duplicating the logic behind the expiration.
  """
  def expire_at(state, key, timestamp),
  do: expire(state, key, timestamp - Util.now())

  @doc """
  Retrieves a list of keys from the cache. This is surprisingly fast, because we
  use a funky selection, but all the same it should be used less frequently as
  the payload being copied and sent back over the server is potentially costly.
  """
  def keys(state) do
    state.cache
    |> :mnesia.dirty_select(Util.retrieve_all_rows(:"$1"))
    |> Util.ok
  end

  @doc """
  Removes a TTL from a given key (and is safe if a key does not already have a
  TTL provided). We pass this to `expire/3` to avoid duplicating the update logic.
  """
  def persist(state, key),
  do: expire(state, key, nil)

  @doc """
  Determines the current size of the cache, as returned by the info function. This
  is going to be accurate to the millisecond at the very worst, so we can safely
  provide this implementation for all actions.
  """
  def size(state) do
    state.cache
    |> :mnesia.table_info(:size)
    |> Util.ok
  end

  @doc """
  Returns the time remaining on a key before expiry. The value returned is in
  milliseconds. If the key has no expiration, nil is returned. This function
  delegates to the actions modules to allow for optimizations.
  """
  def ttl(state, key),
  do: do_action(state, :ttl, [key])

  # Forwards a call to the correct actions set, currently only the local actions.
  # The idea is that in future this will delegate to distributed implementations,
  # so it has been built out in advance to provide a clear migration path.
  defp do_action(state, action, args \\ []),
  do: apply(__MODULE__.Local, action, [state|args])

end
