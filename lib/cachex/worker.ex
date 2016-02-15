defmodule Cachex.Worker do
  use Cachex.Macros
  use GenServer

  # alias stats
  alias Cachex.Stats

  @moduledoc false
  # The main workers for Cachex, providing access to the backing tables using a
  # GenServer implementation. This is separated into a new process as we store a
  # state containing various options (fallbacks, ttls, etc). It also allows the
  # owner process to pool workers to avoid the bottlenecks which come with a
  # single GenServer.

  defstruct cache: nil,   # the cache name (unused, but worth tracking)
            table: nil,   # the name of the backing table
            stats: nil    # a potential struct to store stats in

  @doc """
  Simple initialization for use in the main owner process in order to start an
  instance of a worker. All options are passed throught to the initialization
  function, and the GenServer options are passed straight to GenServer to deal
  with.
  """
  def start_link(options \\ [], gen_options \\ []) do
    GenServer.start(__MODULE__, options, gen_options)
  end

  @doc """
  Main initialization phase of a worker, creating a stats struct as required and
  creating the initial state for this worker. The state is then passed through
  for use in the future.
  """
  def init(options \\ []) do
    stats = case options[:record_stats] do
      val when val == nil or val == false -> nil
      _true -> %Cachex.Stats{
        creationDate: :os.system_time(1000)
      }
    end

    state = %__MODULE__{
      cache: options[:cache],
      table: options[:table],
      stats: stats
    }

    { :ok, state }
  end

  @doc """
  Basic key/value retrieval. Does a lookup on the key, and if the key exists we
  feed the value back to the user, otherwise we feed a nil back to the user.
  """
  defcall get(key) do
    { state, res } = case :ets.lookup(state.table, key) do
      [{ ^key, value }] ->
        { Stats.add_hit(state), value }
      _unrecognised_val ->
        { Stats.add_miss(state), nil }
    end

    res
    |> ok
    |> reply(state)
  end

  @doc """
  Grabs a list of keys for the user (the entire keyspace). This is pretty costly
  (as far as things go), so should be avoided except when debugging.
  """
  defcall keys do
    res = :ets.foldr(fn({ key, _value }, keys) ->
      [key|keys]
    end, [], state.table)

    res
    |> ok
    |> reply(Stats.add_op(state))
  end

  @doc """
  Basic key/value setting. Simply inserts the key into the table alongside the
  value. The user receives `true` as output, because all writes should succeed.
  """
  defcall set(key, value) do
    :ets.insert(state.table, { key, value })
    |> ok
    |> reply(Stats.add_set(state))
  end

  @doc """
  Increments a value by a given amount, setting the value to an initial value if
  it does not already exist. The value returned is the value *after* increment.
  """
  defcall inc(key, amount, initial) do
    new_count = :ets.update_counter(
      state.table, key, { 2, amount }, { key, initial }
    )

    new_count
    |> ok
    |> reply(Stats.add_op(state))
  end

  @doc """
  Removes a key/value pair from the cache.
  """
  defcall delete(key) do
    :ets.delete(state.table, key)
    |> ok
    |> reply(Stats.add_eviction(state))
  end

  @doc """
  Removes a key/value pair from the cache, but returns the last known value of
  the key as it existed in the cache on removal.
  """
  defcall take(key) do
    res = case :ets.take(state.table, key) do
      [{ ^key, value }] -> value
      _unrecognised_val -> nil
    end

    res
    |> ok
    |> reply(Stats.add_eviction(state))
  end

  @doc """
  Removes all values from the cache.
  """
  defcall clear do
    eviction_count = if state.stats do
      get_size(state)
    end

    :ets.delete_all_objects(state.table)
    |> ok
    |> reply(Stats.add_eviction(state, eviction_count))
  end

  @doc """
  Returns valuable information about the table backing the cache.
  """
  defcall info do
    state
    |> get_info
    |> ok
    |> reply(Stats.add_op(state))
  end

  @doc """
  Determines whether the cache is empty or not, returning a boolean representing
  the state.
  """
  defcall empty? do
    (get_size(state) == 0)
    |> ok
    |> reply(Stats.add_op(state))
  end

  @doc """
  Determines whether a key exists in the cache. When the intention is to retrieve
  the value, it's faster to do a blind get and check for nil.
  """
  defcall exists?(key) do
    :ets.member(state.table, key)
    |> ok
    |> reply(Stats.add_op(state))
  end

  @doc """
  Determines the current size of the cache, as returned by the info function.
  """
  defcall size do
    state
    |> get_size
    |> ok
    |> reply(Stats.add_op(state))
  end

  @doc """
  Returns the internal stats for this worker if they're enabled, otherwise an
  error tuple is returned.
  """
  defcall stats do
    if state.stats do
      state.stats
      |> ok
      |> reply(state)
    else
      reply({ :error, "Stats not enabled for cache named '#{state.cache}'"}, state)
    end
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

  # Retrieves the ETS information for a given state.
  # It simply extracts the name from the state and passes
  # straight to `:ets.info/1`. This is needed because we
  # use it in multiple locations.
  defp get_info(state) do
    :ets.info(state.table)
  end

  # Retrieves the size information for a given ETS table.
  # It simply plucks the `:size` field from `get_info/1`.
  defp get_size(state) do
    get_info(state)[:size]
  end

  # Lazy wrapper for `:ok` results
  defp ok(value), do: { :ok, value }

  # Lazy wrapper for `handle_call` results
  defp reply(value, state) do
    { :reply, value, state }
  end

end
