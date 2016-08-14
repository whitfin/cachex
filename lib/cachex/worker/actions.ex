defmodule Cachex.Worker.Actions do
  # ensure we use the actions interface
  @behaviour Cachex.Worker

  @moduledoc false
  # This module defines the backing actions a worker can take. Functions in this
  # module use Mnesia when inside a trnasaction context, otherwise they use ETS.
  # This allows us to provid the fastest possible throughput for a simple local,
  # in-memory cache. Please note that when calling functions from inside this
  # module (internal functions), you should go through the Worker parent module
  # to avoid creating potentially messy internal dependency.

  # add some aliases
  alias Cachex.Util
  alias Cachex.Worker

  # define purge constants
  @purge_override [{ :via, { :purge } }, { :hook_result, { :ok, 1 } }]

  @doc """
  Writes a record into the cache, and returns a result signifying whether the
  write was successful or not.
  """
  def write(%{ cache: cache }, record) do
    detect_transaction(
      fn ->
        insert_res = :ets.insert(cache, record)
        Util.create_truthy_result(insert_res)
      end,
      fn ->
        insert_res = :mnesia.write(cache, record, :write)
        Util.create_truthy_result(insert_res == :ok)
      end
    )
  end

  @doc """
  Reads back a key from the cache.

  If the key does not exist we return a `nil` value. If the key has expired, we
  delete it from the cache using the `:purge` action as a notification.
  """
  def read(%{ cache: cache } = state, key) do
    read_result = detect_transaction(
      fn -> :ets.lookup(cache, key) end,
      fn -> :mnesia.read(cache, key) end
    )

    case read_result do
      [{ _cache, ^key, touched, ttl, _value } = record] ->
        if Util.has_expired?(state, touched, ttl) do
          Worker.del(state, key, @purge_override)
          nil
        else
          record
        end
      _unrecognised_val ->
        nil
    end
  end

  @doc """
  Updates a number of fields in a record inside the cache, by key.

  For ETS, we do this entirely in a single sweep. For Mnesia, we need to use a
  two-step get/update from the Worker interface to accomplish the same. We then
  use a reduction to modify the Tuple.
  """
  def update(state, key, changes) do
    detect_transaction(
      fn ->
        update_res = :ets.update_element(state.cache, key, changes)
        Util.create_truthy_result(update_res)
      end,
      fn ->
        wrapped = List.wrap(changes)

        Worker.get_and_update_raw(state, key, fn(record) ->
          Enum.reduce(wrapped, record, fn({ position, value }, record) ->
            put_elem(record, position - 1, value)
          end)
        end)

        { :ok, true }
      end
    )
  end

  @doc """
  Removes a record from the cache using the provided key.

  Regardless of whether the key exists or not, we return a truthy value (to signify
  the record is not in the cache any longer).
  """
  def delete(%{ cache: cache }, key) do
    detect_transaction(
      fn ->
        cache
        |> :ets.delete(key)
        |> Util.ok
      end,
      fn ->
        del_result = :mnesia.delete(cache, key, :write)
        Util.create_truthy_result(del_result == :ok)
      end
    )
  end

  @doc """
  Empties the cache entirely.

  When outside of a transaction context, we empty the table and return the number
  of deleted records. Inside a transaction we have to return an error, as Mnesia
  cannot handle a clear operation when already inside a transaction. This is noted
  inside the README.
  """
  def clear(%{ cache: cache } = state, _options) do
    eviction_count = case Worker.size(state, notify: false) do
      { :ok, size } -> size
      _other_value_ -> 0
    end

    detect_transaction(
      fn ->
        :ets.delete_all_objects(cache)
        Util.ok(eviction_count)
      end,
      fn -> { :error, :nested_transaction } end
    )
  end

  @doc """
  Increments a given key by a given amount.

  For ETS, we do this using the internal `update_counter/4` function. For Mnesia
  we use `Cachex.Worker.get_and_update/4` to achieve the same.

  If the record is missing, we insert a new one based on the passed values (but
  it has no TTL). We return the value after it has been incremented.
  """
  def incr(state, key, options) do
    amount =
      options
      |> Util.get_opt_number(:amount, 1)

    initial =
      options
      |> Util.get_opt_number(:initial, 0)

    detect_transaction(
      fn ->
        new_record = Util.create_record(state, key, initial)
        exists_key = Worker.exists?(state, key, notify: false)

        try do
          new_value =
            state.cache
            |> :ets.update_counter(key, { 5, amount }, new_record)

          case exists_key do
            { :ok, true } ->
              { :ok, new_value }
            { :ok, false } ->
              { :missing, new_value }
          end
        rescue
          _e -> { :error, :non_numeric_value }
        end
      end,
      fn ->
        Worker.get_and_update(state, key, fn
          (val) when is_number(val) ->
            val + amount
          (nil) ->
            initial + amount
          (_na) ->
            Cachex.abort(state, :non_numeric_value)
        end, notify: false)
      end
    )
  end

  @doc """
  This is like `del/2` but it returns the last known value of the key as it
  existed in the cache upon deletion.
  """
  def take(state, key, _options) do
    detect_transaction(
      fn ->
        case :ets.take(state.cache, key) do
          [{ _cache, ^key, touched, ttl, value }] ->
            if Util.has_expired?(touched, ttl) do
              { :missing, nil }
            else
              { :ok, value }
            end
          _unrecognised_val ->
            { :missing, nil }
        end
      end,
      fn ->
        value = case read(state, key) do
          { _cache, ^key, _touched, _ttl, value } ->
            { :ok, value }
          _unrecognised_val ->
            { :missing, nil }
        end

        unless match?({ _, nil }, value) do
          Worker.del(state, key, notify: false)
        end

        value
      end
    )
  end

  # Internal detection method used to execute functions based on whether we're in
  # a transactional context. If we are, we take the second argument. Otherwise
  # we execute the first.
  defp detect_transaction(ets_action, mnesia_action) do
    if :mnesia.is_transaction() do
      mnesia_action.()
    else
      ets_action.()
    end
  end

end
