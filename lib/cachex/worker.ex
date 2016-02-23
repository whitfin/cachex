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
  alias Cachex.Stats
  alias Cachex.Util
  alias Cachex.Worker.Actions

  # define internal struct
  defstruct cache: nil,     # the cache name
            options: nil,   # the options of this cache
            stats: nil      # a potential struct to store stats in

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
      cache: options.cache,
      options: options,
      stats: options.record_stats && %Cachex.Stats{
        creationDate: Util.now()
      } || nil
    }
    { :ok, state }
  end

  @doc """
  Retrieves a value from the cache.
  """
  defcall get(key, fallback_function) do
    { state, res } = case Actions.get(state, key, fallback_function) do
      { :loaded, val } ->
        { Stats.add_load(state), val }
      { :ok, nil } ->
        { Stats.add_miss(state), nil }
      { :ok, val } ->
        { Stats.add_hit(state), val }
    end

    res
    |> Util.ok
    |> Util.reply(state)
  end

  @doc """
  Retrieves and updates a value in the cache.
  """
  defcall get_and_update(key, update_fun, fb_fun) do
    { state, res } = case Actions.get_and_update(state, key, update_fun, fb_fun) do
      { :ok, _value } = res ->
        { Stats.add_set(state), res }
      other ->
        { state, other }
    end
    Util.reply(res, state)
  end

  @doc """
  Sets a value in the cache.
  """
  defcall set(key, value, ttl) do
    { state, res } = case Actions.set(state, key, value, ttl) do
      { :ok, _value } = res ->
        { Stats.add_set(state), res }
      errored_values ->
        { state, errored_values }
    end
    Util.reply(res, state)
  end

  @doc """
  Increments a value in the cache.
  """
  defcall incr(key, amount, initial, touched) do
    state
    |> Stats.add_op
    |> Actions.incr(key, amount, initial, touched)
    |> Util.reply(state)
  end

  @doc """
  Removes all keys from the cache.
  """
  defcall clear do
    { state, res } = case Actions.clear(state) do
      { :ok, nil } = res ->
        { state, res }
      { :ok, val } = res ->
        { Stats.add_eviction(state, val), res }
    end

    Util.reply(res, state)
  end

  @doc """
  Removes a key from the cache.
  """
  defcall del(key) do
    state
    |> Stats.add_eviction
    |> Actions.del(key)
    |> Util.reply(state)
  end

  @doc """
  Removes a key from the cache, returning the last known value for the key.
  """
  defcall take(key) do
    { state, res } = case Actions.take(state, key) do
      { :ok, nil } = res ->
        { Stats.add_miss(state), res }
      { :ok, _val } = res ->
        { Stats.add_eviction(state), res }
    end

    Util.reply(res, state)
  end

  @doc """
  Determines whether a key exists in the cache.
  """
  defcall exists?(key) do
    state
    |> Stats.add_op
    |> Actions.exists?(key)
    |> Util.reply(state)
  end

  @doc """
  Refreshes the expiration on a given key based on the value passed in.
  """
  defcall expire(key, expiration) do
    state
    |> Stats.add_op
    |> Actions.expire(key, expiration)
    |> Util.reply(state)
  end

  @doc """
  Refreshes the expiration on a given key to match the timestamp passed in.
  """
  defcall expire_at(key, timestamp) do
    state
    |> Stats.add_op
    |> Actions.expire_at(key, timestamp)
    |> Util.reply(state)
  end

  @doc """
  Grabs a list of keys for the user (the entire keyspace).
  """
  defcall keys do
    state
    |> Stats.add_op
    |> Actions.keys
    |> Util.reply(state)
  end

  @doc """
  Removes a set TTL from a given key.
  """
  defcall persist(key) do
    state
    |> Stats.add_op
    |> Actions.persist(key)
    |> Util.reply(state)
  end

  @doc """
  Determines the current size of the cache.
  """
  defcall size do
    state
    |> Stats.add_op
    |> Actions.size
    |> Util.reply(state)
  end

  @doc """
  Returns the internal stats for this worker.
  """
  defcall stats do
    if state.stats do
      state.stats
      |> Stats.finalize
      |> Util.ok
      |> Util.reply(state)
    else
      Util.reply({ :error, "Stats not enabled for cache named '#{state.cache}'" }, state)
    end
  end

  @doc """
  Returns the time remaining on a key before expiry. The value returned it in
  milliseconds. If the key has no expiration, nil is returned.
  """
  defcall ttl(key) do
    state
    |> Stats.add_op
    |> Actions.ttl(key)
    |> Util.reply(state)
  end

  @doc """
  Called by the janitor process to signal evictions being added. We only care
  about this being reported when stats are enabled for this cache.
  """
  defcast add_evictions(count) do
    { :noreply, Stats.add_expiration(state, count) }
  end

end
