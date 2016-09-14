defmodule Cachex.Actions.Inspect do
  @moduledoc false

  alias Cachex.Errors
  alias Cachex.State
  alias Cachex.Util

  # Returns information about the expired keys currently inside the cache (i.e.
  # keys which  will be purged in the next Janitor run).
  def execute(%State{ cache: cache }, { :expired, :count }) do
    { :ok, :ets.select_count(cache, Util.retrieve_expired_rows(true)) }
  end
  def execute(%State{ cache: cache }, { :expired, :keys }) do
    { :ok, :ets.select(cache, Util.retrieve_expired_rows(:key)) }
  end
  def execute(_cache, { :expired, _unknown }) do
    { :error, "Invalid expiration inspection type provided" }
  end

  # Returns information about the last run of the Janitor process (if there is one).
  def execute(%State{ janitor: ref }, { :janitor, :last }) do
    if :erlang.whereis(ref) != :undefined do
      { :ok, GenServer.call(ref, :last) }
    else
      Errors.janitor_disabled()
    end
  end

  # Requests the memory information from a cache, and converts it using the word
  # size of the system, in order to return a number of bytes or as a binary.
  def execute(%State{ cache: cache }, { :memory, type }) do
    mem_words = :erlang.system_info(:wordsize)
    mem_cache = :ets.info(cache, :memory)

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
  def execute(state, option) when option in [ :state, :worker ] do
    { :ok, State.get(state.cache) }
  end

  # If we hit this point, we're not handling the options explicitly, so we just
  # send back an error to to the caller.
  def execute(_cache, _option) do
    Errors.invalid_option()
  end

end
