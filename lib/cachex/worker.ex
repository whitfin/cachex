defmodule Cachex.Worker do
  # use Macros and GenServer
  use Cachex.Macros.GenServer
  use GenServer

  @moduledoc false
  # The main worker for Cachex, providing access to the backing tables using a
  # GenServer implementation. This is separated into a new process as we store a
  # state containing various options (fallbacks, ttls, etc). It also avoids us
  # blocking the main process for long-running actions (e.g. we can always provide
  # cast functions).

  # add some aliases
  alias Cachex.Hook
  alias Cachex.Notifier
  alias Cachex.Stats
  alias Cachex.Util
  alias Cachex.Worker.Actions

  # define internal struct
  defstruct actions: nil,   # the actions implementation
            cache: nil,     # the cache name
            options: nil,   # the options of this cache
            stats: nil      # the ref for where stats can be found

  @doc """
  Simple initialization for use in the main owner process in order to start an
  instance of a worker. All options are passed throught to the initialization
  function, and the GenServer options are passed straight to GenServer to deal
  with.
  """
  def start_link(options \\ %Cachex.Options { }, gen_options \\ []) do
    GenServer.start(__MODULE__, options, gen_options)
  end

  @doc """
  Main initialization phase of a worker, plucking out the options we care about
  and storing them internally for later use by this worker.
  """
  def init(options \\ %Cachex.Options { }) do
    state = %__MODULE__{
      actions: cond do
        options.remote ->
          Actions.Remote
        options.transactional ->
          Actions.Transactional
        true ->
          Actions.Local
      end,
      cache: options.cache,
      options: options,
      stats: Hook.ref_by_module(options.post_hooks, Cachex.Stats)
    }
    { :ok, state }
  end

  @doc """
  Retrieves a value from the cache.
  """
  defcall get(key, options) do
    state
    |> Actions.get(key, options)
  end

  @doc """
  Retrieves and updates a value in the cache.
  """
  defcall get_and_update(key, update_fun, options) do
    state
    |> Actions.get_and_update(key, update_fun, options)
  end

  @doc """
  Sets a value in the cache.
  """
  defcc set(key, value, options) do
    Actions.set(state, key, value, options)
  end

  @doc """
  Updates a value in the cache.
  """
  defcc update(key, value, options) do
    Actions.update(state, key, value, options)
  end

  @doc """
  Removes a key from the cache.
  """
  defcc del(key, options) do
    state
    |> Actions.del(key, options)
  end

  @doc """
  Removes all keys from the cache.
  """
  defcc clear(options) do
    state
    |> Actions.clear(options)
  end

  @doc """
  Like size, but more accurate - takes into account expired keys.
  """
  defcall count(options) do
    state
    |> Actions.count(options)
  end

  @doc """
  Determines whether a key exists in the cache.
  """
  defcall exists?(key, options) do
    state
    |> Actions.exists?(key, options)
  end

  @doc """
  Refreshes the expiration on a given key based on the value passed in.
  """
  defcc expire(key, expiration, options) do
    state
    |> Actions.expire(key, expiration, options)
  end

  @doc """
  Refreshes the expiration on a given key to match the timestamp passed in.
  """
  defcc expire_at(key, timestamp, options) do
    state
    |> Actions.expire_at(key, timestamp, options)
  end

  @doc """
  Grabs a list of keys for the user (the entire keyspace).
  """
  defcall keys(options) do
    state
    |> Actions.keys(options)
  end

  @doc """
  Increments a value in the cache.
  """
  defcc incr(key, amount, options) do
    state
    |> Actions.incr(key, amount, options)
  end

  @doc """
  Removes a set TTL from a given key.
  """
  defcc persist(key, options) do
    state
    |> Actions.persist(key, options)
  end

  @doc """
  Purges all expired keys.
  """
  defcc purge(options) do
    state
    |> Actions.purge(options)
  end

  @doc """
  Refreshes the expiration time on a key.
  """
  defcc refresh(key, options) do
    state
    |> Actions.refresh(key, options)
  end

  @doc """
  Determines the current size of the cache.
  """
  defcall size(options) do
    state
    |> Actions.size(options)
  end

  @doc """
  Returns the current state of this worker.
  """
  defcall state,
  do: state

  @doc """
  Returns the internal stats for this worker.
  """
  defcall stats(_options) do
    if state.stats do
      state.stats
      |> Stats.retrieve
      |> Util.ok
    else
      { :error, "Stats not enabled for cache with ref '#{state.cache}'" }
    end
  end

  @doc """
  Removes a key from the cache, returning the last known value for the key.
  """
  defcall take(key, options) do
    state
    |> Actions.take(key, options)
  end

  @doc """
  Returns the time remaining on a key before expiry. The value returned it in
  milliseconds. If the key has no expiration, nil is returned.
  """
  defcall ttl(key, options) do
    state
    |> Actions.ttl(key, options)
  end

  @doc """
  Called by the janitor process to signal evictions being added. We only care
  about this being reported when stats are enabled for this cache.
  """
  defcast record_purge(count) do
    do_action(state, [:purge], fn ->
      { :ok, count }
    end)
    { :noreply, state }
  end

  # Forwards a call to the correct actions set, currently only the local actions.
  # The idea is that in future this will delegate to distributed implementations,
  # so it has been built out in advance to provide a clear migration path.
  def do_action(%Cachex.Worker{ } = state, message, fun)
  when is_list(message) and is_function(fun) do
    case state.options.pre_hooks do
      [] -> nil;
      li -> Notifier.notify(li, Util.list_to_tuple(message))
    end

    result = fun.()

    case state.options.post_hooks do
      [] -> nil;
      li -> Notifier.notify(li, Util.list_to_tuple(message), result)
    end

    result
  end

end
