defmodule Cachex.Worker do
  # use Macros and GenServer
  use Cachex.Util.Macros
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
  defcall get(key, fallback_function) do
    state
    |> Actions.get(key, fallback_function)
    |> Util.reply(state)
  end

  @doc """
  Retrieves and updates a value in the cache.
  """
  defcall get_and_update(key, update_fun, fb_fun) do
    state
    |> Actions.get_and_update(key, update_fun, fb_fun)
    |> Util.reply(state)
  end

  @doc """
  Sets a value in the cache.
  """
  defcall set(key, value, ttl) do
    state
    |> Actions.set(key, value, ttl)
    |> Util.reply(state)
  end

  @doc """
  Increments a value in the cache.
  """
  defcall incr(key, amount, initial) do
    state
    |> Actions.incr(key, amount, initial)
    |> Util.reply(state)
  end

  @doc """
  Removes all keys from the cache.
  """
  defcall clear do
    state
    |> Actions.clear
    |> Util.reply(state)
  end

  @doc """
  Removes a key from the cache.
  """
  defcall del(key) do
    state
    |> Actions.del(key)
    |> Util.reply(state)
  end

  @doc """
  Like size, but more accurate - takes into account expired keys.
  """
  defcall count do
    state
    |> Actions.count
    |> Util.reply(state)
  end

  @doc """
  Determines whether a key exists in the cache.
  """
  defcall exists?(key) do
    state
    |> Actions.exists?(key)
    |> Util.reply(state)
  end

  @doc """
  Refreshes the expiration on a given key based on the value passed in.
  """
  defcall expire(key, expiration) do
    state
    |> Actions.expire(key, expiration)
    |> Util.reply(state)
  end

  @doc """
  Refreshes the expiration on a given key to match the timestamp passed in.
  """
  defcall expire_at(key, timestamp) do
    state
    |> Actions.expire_at(key, timestamp)
    |> Util.reply(state)
  end

  @doc """
  Grabs a list of keys for the user (the entire keyspace).
  """
  defcall keys do
    state
    |> Actions.keys
    |> Util.reply(state)
  end

  @doc """
  Removes a set TTL from a given key.
  """
  defcall persist(key) do
    state
    |> Actions.persist(key)
    |> Util.reply(state)
  end

  @doc """
  Purges all expired keys.
  """
  defcall purge do
    state
    |> Actions.purge
    |> Util.reply(state)
  end

  @doc """
  Refreshes the expiration time on a key.
  """
  defcall refresh(key) do
    state
    |> Actions.refresh(key)
    |> Util.reply(state)
  end

  @doc """
  Determines the current size of the cache.
  """
  defcall size do
    state
    |> Actions.size
    |> Util.reply(state)
  end

  @doc """
  Returns the current state of this worker.
  """
  defcall state,
  do: Util.reply(state, state)

  @doc """
  Returns the internal stats for this worker.
  """
  defcall stats do
    if state.stats do
      state.stats
      |> Stats.retrieve
      |> Util.ok
      |> Util.reply(state)
    else
      Util.reply({ :error, "Stats not enabled for cache named '#{state.cache}'" }, state)
    end
  end

  @doc """
  Removes a key from the cache, returning the last known value for the key.
  """
  defcall take(key) do
    state
    |> Actions.take(key)
    |> Util.reply(state)
  end

  @doc """
  Returns the time remaining on a key before expiry. The value returned it in
  milliseconds. If the key has no expiration, nil is returned.
  """
  defcall ttl(key) do
    state
    |> Actions.ttl(key)
    |> Util.reply(state)
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
  def do_action(_state, _action, _args \\ [])
  def do_action(%Cachex.Worker{ actions: actions } = state, action, args)
  when is_atom(action) and is_list(args) do
    do_action(state, [action|args], fn ->
      apply(actions, action, [state|args])
    end)
  end
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
