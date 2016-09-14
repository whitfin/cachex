defmodule Cachex.Hook.Stats do
  @moduledoc false
  # A simple statistics container, used to keep track of various operations on
  # a given cache. This is used as a post hook for a cache and provides an example
  # of what a hook can look like. This container has no knowledge of the cache
  # it belongs to, it only keeps track of an internal struct.

  # use the hooks
  use Cachex.Hook

  @doc """
  Initializes a new stats container, setting the creation date to the current time.

  This state will be passed into each handler in this server.
  """
  def init(_options \\ []) do
    { :ok, %{ meta: %{ creationDate: Cachex.Util.now() } } }
  end

  @doc """
  Forward any successful calls through to the stats container.

  We don't keep statistics on requests which errored, to avoid false positives
  about what exactly is going on inside a given cache.
  """
  def handle_notify({ action, _options }, { status, _val } = result, stats) when status != :error do
    { :ok, Cachex.Stats.register(action, result, stats) }
  end

  @doc """
  Handles a call to retrieve the stats as they currently stand. We finalize the
  stats and return them to the calling process.
  """
  def handle_call(:retrieve, stats) do
    { :ok, stats, stats }
  end

  def retrieve(ref) do
    GenEvent.call(ref, __MODULE__, :retrieve)
  end

end
