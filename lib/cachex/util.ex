defmodule Cachex.Util do
  @moduledoc false
  # A small collection of utilities for use hroughout the library. Mainly things
  # to do with response formatting and generally just common functions.

  @doc """
  Consistency wrapper around current time in millis.
  """
  def now, do: :os.system_time(1000)

  @doc """
  Lazy wrapper for creating an :error tuple.
  """
  def error(value), do: { :error, value }

  @doc """
  Lazy wrapper for creating an :ok tuple.
  """
  def ok(value), do: { :ok, value }

  @doc """
  Lazy wrapper for creating a :noreply tuple.
  """
  def noreply(value), do: { :noreply, value }

  @doc """
  Lazy wrapper for creating a :reply tuple.
  """
  def reply(value, state), do: { :reply, value, state }

  @doc """
  Creates an input record based on a key, value and expiration. If the value
  passed is nil, then we apply any defaults. Otherwise we add the value
  to the current time (in milliseconds) and return a tuple for the table.
  """
  def create_record(state, key, value, expiration \\ nil) do
    exp = case expiration do
      nil -> state.options.default_ttl
      val -> val
    end
    { state.cache, key, now(), exp, value }
  end

  @doc """
  Retrieves a fallback value for a given key, using either the provided function
  or using the default fallback implementation.
  """
  def get_fallback(state, key, fb_fun \\ nil, default_val \\ nil) do
    fun = cond do
      is_function(fb_fun) ->
        fb_fun
      is_function(state.options.default_fallback) ->
        state.options.default_fallback
      true ->
        default_val
    end

    case fun do
      nil -> nil
      val ->
        case :erlang.fun_info(val)[:arity] do
          1 -> val.(key)
          _ -> val.(key, state.options.fallback_args)
        end
    end
  end

  @doc """
  Takes a result in the format of a transaction result and returns just either
  the value or the error as an ok/error tuple. You can provide an overload value
  if you wish to ignore the transaction result and return a different value, but
  whilst still checking for errors.
  """
  def handle_transaction({ :atomic, { :error, _ } = err}), do: err
  def handle_transaction({ :atomic, { :ok, _ } = res}), do: res
  def handle_transaction({ :atomic, value }), do: ok(value)
  def handle_transaction({ :aborted, reason }), do: error(reason)
  def handle_transaction({ :atomic, _value }, value), do: ok(value)
  def handle_transaction({ :aborted, reason }, _value), do: error(reason)

  @doc """
  Small utility to figure out if a document has expired based on the last touched
  time and the TTL of the document.
  """
  def has_expired(_touched, nil), do: false
  def has_expired(touched, ttl), do: touched + ttl < now

  @doc """
  Returns a selection to return the designated value for all rows. Enables things
  like finding all stored keys and all stored values.
  """
  def retrieve_all_rows(return) do
    [
      {
        { :"_", :"$1", :"$2", :"$3", :"$4" },       # input (our records)
        [
          {
            :orelse,                                # guards for matching
            { :"==", :"$3", nil },                  # where a TTL is set
            { :"<", { :"+", :"$2", :"$3" }, now }   # and the TTL has passed
          }
        ],
        [ return ]                                  # our output
      }
    ]
  end

end
