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
  def reply(value, state), do: { :reply, value, state}

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

end
