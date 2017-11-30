defmodule Cachex.Hook.Stats do
  @moduledoc false
  # A simple statistics container, used to keep track of various operations on
  # a given cache. This is used as a post hook for a cache and provides an example
  # of what a hook can look like. This container has no knowledge of the cache
  # it belongs to, it only keeps track of an internal Map of statistics.
  import Cachex.Spec

  # use the hooks
  use Cachex.Hook

  # add some aliases
  alias Cachex.Stats

  @doc """
  Initializes a new stats Map.

  We set a `:creationDate` field inside the `:meta` sub-Map to contain the date
  that the statistics were first created.
  """
  def init(_options),
    do: { :ok, %{ meta: %{ creationDate: now() } } }

  @doc """
  Registers actions against the stats container.

  If a request to the cache has errored for any reason, we don't track it just
  to ensure that we don't have any false positives of actions taken. The heavy
  lifting here is done by the logic in `Cachex.Stats` where it's generic, rather
  than being embedded into the Hook definition itself.
  """
  def handle_notify(_action, { :error, _result }, stats),
    do: { :ok, stats }
  def handle_notify({ action, _options }, result, stats),
    do: { :ok, Stats.register(action, result, stats) }

  @doc """
  Returns the current stats container to the calling process.
  """
  def handle_call(:retrieve, _ctx, stats),
    do: { :reply, stats, stats }
end
