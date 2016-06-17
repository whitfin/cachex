defmodule Cachex.Inspector do
  @moduledoc false
  # An in-proc inspector for a cache and cache state. Anything done in here is
  # isolated from the cache and so any slow running inspections will only impact
  # the calling process, rather than the cache itself.
  #
  # Any table interactions in here should go via `:mnesia` and the dirty operations
  # inside, rather than via ETS. This is a couple of microseconds slower for operations
  # but at least we can be sure we're getting an accurate view.

  # alias some modules
  alias Cachex.Util
  alias Cachex.Worker

  # state based inspections
  @state_based [ :state, :worker ]

  @doc """
  We don't care about having a worker instance, only the name of the internal table,
  so we pass through only the cache name as needed.
  """
  def inspect(%Worker{ cache: cache }, option) when not option in @state_based do
    __MODULE__.inspect(cache, option)
  end

  @doc """
  Returns information about the expired keys currently inside the cache (i.e. keys
  which  will be purged in the next Janitor run).
  """
  def inspect(cache, { :expired, :count }) do
    query = Util.retrieve_expired_rows(true)
    cache
    |> :ets.select_count(query)
    |> Util.ok
  end
  def inspect(cache, { :expired, :keys }) do
    query = Util.retrieve_expired_rows(:key)
    cache
    |> :ets.select(query)
    |> Util.ok
  end
  def inspect(_cache, { :expired, _unknown }) do
    { :error, "Invalid expiration inspection type provided" }
  end

  @doc """
  Returns information about the last run of the Janitor process (if there is one).
  """
  def inspect(cache, { :janitor, :last }) do
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

  @doc """
  Requests the memory information from a cache, and converts it using the word
  size of the system, in order to return a number of bytes or as a binary.
  """
  def inspect(cache, { :memory, type }) do
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

  @doc """
  Requests the internal state of a cache worker.
  """
  def inspect(cache, option) when option in [ :state, :worker ] do
    { :ok, cache }
  end

  @doc """
  If we hit this point, we're not handling the options explicitly, so we just send
  back an error to to the caller.
  """
  def inspect(_cache, _option) do
    { :error, "Invalid inspect option provided" }
  end

end
