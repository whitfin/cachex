defmodule Cachex.Util do
  @moduledoc false
  # A small collection of useful things throughout the library

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

end
