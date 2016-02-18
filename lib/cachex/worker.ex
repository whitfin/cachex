defmodule Cachex.Worker do
  use Cachex.Util.Macros
  use GenServer

  # alias internals
  alias Cachex.Stats
  alias Cachex.Util
  alias Cachex.Worker.Actions

  @moduledoc false
  # The main workers for Cachex, providing access to the backing tables using a
  # GenServer implementation. This is separated into a new process as we store a
  # state containing various options (fallbacks, ttls, etc). It also allows the
  # owner process to pool workers to avoid the bottlenecks which come with a
  # single GenServer.

  defstruct cache: nil,         # the cache name
            default_ttl: nil,   # the time a record lives
            interval: nil,      # the ttl check interval
            stats: nil          # a potential struct to store stats in

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
  Main initialization phase of a worker, creating a stats struct as required and
  creating the initial state for this worker. The state is then passed through
  for use in the future.
  """
  def init(options \\ %Cachex.Options { }) do
    state = %__MODULE__{
      cache: options.cache,
      default_ttl: options.default_ttl,
      interval: options.ttl_interval,
      stats: options.stats
    }
    { :ok, state }
  end

  @doc """
  Basic key/value retrieval. Does a lookup on the key, and if the key exists we
  feed the value back to the user, otherwise we feed a nil back to the user.
  """
  defcall get(key, fallback_function) do
    { state, res } = case Actions.get(state, key, fallback_function) do
      { :lookup, val } ->
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
  Grabs a list of keys for the user (the entire keyspace). This is pretty costly
  (as far as things go), so should be avoided except when debugging.
  """
  defcall keys do
    state
    |> Actions.keys
    |> Util.reply(Stats.add_op(state))
  end

  @doc """
  Basic key/value setting. Simply inserts the key into the table alongside the
  value. The user receives `true` as output, because all writes should succeed.
  """
  defcall set(key, value) do
    state
    |> Actions.set(key, value)
    |> Util.reply(Stats.add_set(state))
  end

  @doc """
  Increments a value by a given amount, setting the value to an initial value if
  it does not already exist. The value returned is the value *after* increment.
  """
  defcall inc(key, amount, initial) do
    state
    |> Actions.incr(key, amount, initial)
    |> Util.reply(Stats.add_op(state))
  end

  @doc """
  Removes a key/value pair from the cache.
  """
  defcall delete(key) do
    state
    |> Actions.del(key)
    |> Util.reply(Stats.add_eviction(state))
  end

  @doc """
  Removes a key/value pair from the cache, but returns the last known value of
  the key as it existed in the cache on removal.
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
  Removes all values from the cache.
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
  Determines whether the cache is empty or not, returning a boolean representing
  the state.
  """
  defcall empty? do
    state
    |> Actions.empty?
    |> Util.reply(Stats.add_op(state))
  end

  @doc """
  Determines whether a key exists in the cache. When the intention is to retrieve
  the value, it's faster to do a blind get and check for nil.
  """
  defcall exists?(key) do
    state
    |> Actions.exists?(key)
    |> Util.reply(Stats.add_op(state))
  end

  @doc """
  Refreshes the expiration on a given key based on the value passed in. We drop
  to ETS in order to do an in-place change rather than lock, pull, and update.
  """
  defcall expire(key, expiration) do
    state
    |> Actions.expire(key, expiration)
    |> Util.reply(Stats.add_op(state))
  end

  @doc """
  Refreshes the expiration on a given key to match the timestamp passed in. We
  drop to ETS in order to do an in-place change rather than lock, pull, and update.
  """
  defcall expire_at(key, timestamp) do
    state
    |> Actions.expire_at(key, timestamp)
    |> Util.reply(Stats.add_op(state))
  end

  @doc """
  Removes a set TTL from a given key.
  """
  defcall persist(key) do
    state
    |> Actions.persist(key)
    |> Util.reply(Stats.add_op(state))
  end

  @doc """
  Determines the current size of the cache, as returned by the info function.
  """
  defcall size do
    state
    |> Actions.size
    |> Util.reply(Stats.add_op(state))
  end

  @doc """
  Returns the internal stats for this worker if they're enabled, otherwise an
  error tuple is returned.
  """
  defcall stats do
    if state.stats do
      state.stats
      |> Stats.finalize
      |> Util.ok
      |> Util.reply(state)
    else
      Util.reply({ :error, "Stats not enabled for cache named '#{state.cache}'"}, state)
    end
  end

  @doc """
  Returns the time remaining on a key before expiry. The value returned it in
  milliseconds. If the key has no expiration, nil is returned.
  """
  defcall ttl(key) do
    state
    |> Actions.ttl(key)
    |> Util.reply(Stats.add_op(state))
  end

  @doc """
  Called by the janitor process to signal evictions being added. We only care
  about this being reported when stats are enabled for this cache.
  """
  defcast add_evictions(count) do
    { :noreply, Stats.add_expiration(state, count) }
  end

  @doc """
  Catch-all for casts, to ensure that we don't hit errors when providing an
  invalid message. This should never be hit, but it's here anyway.
  """
  def handle_cast(_msg, state) do
    { :noreply, state }
  end

  @doc """
  Catch-all for info, to ensure that we don't hit errors when providing an
  invalid message. This should never be hit, but it's here anyway.
  """
  def handle_info(_info, state) do
    { :noreply, state }
  end

end
