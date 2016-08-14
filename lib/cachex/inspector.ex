defmodule Cachex.Inspector do
  @moduledoc false
  # An in-proc inspector for a cache and cache state. Anything done in here is
  # isolated from the cache and so any slow running inspections will only impact
  # the calling process, rather than the cache itself.

  # alias some modules
  alias Cachex.State
  alias Cachex.Util

  # state based inspections
  @state_based [ :state, :worker ]

  @doc """
  Inspects a cache using the provided options as inspection flags.

  The return type will vary based on the flags provided.
  """
  @spec inspect(state :: State.t | atom, option :: { } | atom) :: any
  def inspect(state, option), do: do_inspect(state, option)

  # We don't care about having a state instance, only the name of the internal
  # table, so we pass through only the cache name as needed.
  defp do_inspect(%State{ cache: cache }, option) when not option in @state_based do
    do_inspect(cache, option)
  end

  # Returns information about the expired keys currently inside the cache (i.e.
  # keys which  will be purged in the next Janitor run).
  defp do_inspect(cache, { :expired, :count }) do
    query = Util.retrieve_expired_rows(true)
    cache
    |> :ets.select_count(query)
    |> Util.ok
  end
  defp do_inspect(cache, { :expired, :keys }) do
    query = Util.retrieve_expired_rows(:key)
    cache
    |> :ets.select(query)
    |> Util.ok
  end
  defp do_inspect(_cache, { :expired, _unknown }) do
    { :error, "Invalid expiration inspection type provided" }
  end

  # Returns information about the last run of the Janitor process (if there is one).
  defp do_inspect(cache, { :janitor, :last }) do
    ref =
      cache
      |> Util.janitor_for_cache

    if :erlang.whereis(ref) != :undefined do
      ref
      |> GenServer.call(:last)
      |> Util.ok
    else
      { :error, "Janitor not running for cache #{inspect(cache)}" }
    end
  end

  # Requests the memory information from a cache, and converts it using the word
  # size of the system, in order to return a number of bytes or as a binary.
  defp do_inspect(cache, { :memory, type }) do
    mem_words = :erlang.system_info(:wordsize)
    mem_cache = :mnesia.table_info(cache, :memory)

    bytes = mem_words * mem_cache

    case type do
      :bytes ->
        { :ok, bytes }
      type when type in [ :binary, :string ] ->
        { :ok, Util.bytes_to_readable(bytes) }
      _unknown ->
        { :error, "Invalid memory inspection type provided" }
    end
  end

  # Requests the internal state of a cache state.
  defp do_inspect(cache, option) when option in [ :state, :worker ] do
    { :ok, cache }
  end

  # If we hit this point, we're not handling the options explicitly, so we just
  # send back an error to to the caller.
  defp do_inspect(_cache, _option) do
    { :error, "Invalid inspect option provided" }
  end

end
