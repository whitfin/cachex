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
  alias Cachex.Janitor
  alias Cachex.Notifier
  alias Cachex.Options
  alias Cachex.Stats
  alias Cachex.Util

  # define internal struct
  defstruct actions: __MODULE__.Local,  # the actions implementation
            cache: nil,                 # the cache name
            options: %Options{ }        # the options of this cache

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
          __MODULE__.Remote
        options.transactional ->
          __MODULE__.Transactional
        true ->
          __MODULE__.Local
      end,
      cache: options.cache,
      options: options
    }
    { :ok, state }
  end

  ###
  # Publicly exported functions and operations.
  ###

  @doc """
  Retrieves a value from the cache.
  """
  def get(%__MODULE__{ } = state, key, options \\ []) when is_list(options) do
    do_action(state, { :get, key, options }, fn ->
      state.actions.get(state, key, options)
    end)
  end

  @doc """
  Retrieves and updates a value in the cache.
  """
  def get_and_update(%__MODULE__{ } = state, key, update_fun, options \\ [])
  when is_function(update_fun) and is_list(options) do
    do_action(state, { :get_and_update, key, update_fun, options }, fn ->
      fb_fun =
        options
        |> Util.get_opt_function(:fallback)

      is_loaded = case quietly_exists?(state, key) do
        { :ok, false } ->
          case Util.get_fallback_function(state, fb_fun) do
            nil -> false
            val ->
              Util.has_arity?(val, [0, 1, length(state.options.fallback_args) + 1])
          end
        _other_results -> false
      end

      { :ok, result } = get_and_update_raw(state, key, fn({ cache, ^key, touched, ttl, value }) ->
        { cache, key, touched, ttl, case value do
          nil ->
            state
            |> Util.get_fallback(key, fb_fun)
            |> elem(1)
            |> update_fun.()
          val ->
            update_fun.(val)
        end }
      end)

      { is_loaded && :loaded || :ok, elem(result, 4) }
    end)
  end

  @doc """
  Sets a value in the cache.
  """
  def set(%__MODULE__{ } = state, key, value, options \\ []) when is_list(options) do
    do_action(state, { :set, key, value, options }, fn ->
      state.actions.set(state, key, value, options)
    end)
  end

  @doc """
  Updates a value in the cache.
  """
  def update(%__MODULE__{ } = state, key, value, options \\ []) when is_list(options) do
    do_action(state, { :update, key, value, options }, fn ->
      case quietly_exists?(state, key) do
        { :ok, true } ->
          state.actions.update(state, key, value, options)
        _other_value_ ->
          { :missing, false }
      end
    end)
  end

  @doc """
  Removes a key from the cache.
  """
  def del(%__MODULE__{ } = state, key, options \\ []) when is_list(options) do
    do_action(state, { :del, key, options }, fn ->
      state.actions.del(state, key, options)
    end)
  end

  @doc """
  Removes all keys from the cache.
  """
  def clear(%__MODULE__{ } = state, options \\ []) when is_list(options) do
    do_action(state, { :clear, options }, fn ->
      state.actions.clear(state, options)
    end)
  end

  @doc """
  Like size, but more accurate - takes into account expired keys.
  """
  def count(%__MODULE__{ } = state, options \\ []) when is_list(options) do
    do_action(state, { :count, options }, fn ->
      state.cache
      |> :ets.select_count(Util.retrieve_all_rows(true))
      |> Util.ok
    end)
  end

  @doc """
  Executes a block of cache actions inside the cache.
  """
  def execute(%__MODULE__{ } = state, operation, options \\ [])
  when is_function(operation, 1) and is_list(options) do
    state
    |> operation.()
    |> Util.ok
  end

  @doc """
  Determines whether a key exists in the cache.
  """
  def exists?(%__MODULE__{ } = state, key, options \\ []) when is_list(options) do
    do_action(state, { :exists?, key, options }, fn ->
      quietly_exists?(state, key)
    end)
  end

  @doc """
  Refreshes the expiration on a given key based on the value passed in.
  """
  def expire(%__MODULE__{ } = state, key, expiration, options \\ []) when is_list(options) do
    do_action(state, { :expire, key, expiration, options }, fn ->
      case quietly_exists?(state, key) do
        { :ok, true } ->
          state.actions.expire(state, key, expiration, options)
        _other_value_ ->
          { :missing, false }
      end
    end)
  end

  @doc """
  Refreshes the expiration on a given key to match the timestamp passed in.
  """
  def expire_at(%__MODULE__{ } = state, key, timestamp, options \\ []) when is_list(options) do
    do_action(state, { :expire_at, key, timestamp, options }, fn ->
      case quietly_exists?(state, key) do
        { :ok, true } ->
          case timestamp - Util.now() do
            val when val > 0 ->
              state.actions.expire(state, key, val, options)
            _expired_already ->
              del(state, key)
          end
        _other_value_ ->
          { :missing, false }
      end
    end)
  end

  @doc """
  Grabs a list of keys for the user (the entire keyspace).
  """
  def keys(%__MODULE__{ } = state, options \\ []) when is_list(options) do
    do_action(state, { :keys, options }, fn ->
      state.actions.keys(state, options)
    end)
  end

  @doc """
  Increments a value in the cache.
  """
  def incr(%__MODULE__{ } = state, key, options \\ []) when is_list(options) do
    do_action(state, { :incr, key, options }, fn ->
      state.actions.incr(state, key, options)
    end)
  end

  @doc """
  Removes a set TTL from a given key.
  """
  def persist(%__MODULE__{ } = state, key, options \\ []) when is_list(options) do
    do_action(state, { :persist, key, options }, fn ->
      expire(state, key, nil, options)
    end)
  end

  @doc """
  Purges all expired keys.
  """
  def purge(%__MODULE__{ } = state, options \\ []) when is_list(options) do
    do_action(state, { :purge, options }, fn ->
      Janitor.purge_records(state.cache)
    end)
  end

  @doc """
  Refreshes the expiration time on a key.
  """
  def refresh(%__MODULE__{ } = state, key, options \\ []) when is_list(options) do
    do_action(state, { :refresh, key, options }, fn ->
      case quietly_exists?(state, key) do
        { :ok, true } ->
          state.actions.refresh(state, key, options)
        _other_value_ ->
          { :missing, false }
      end
    end)
  end

  @doc """
  Determines the current size of the cache.
  """
  def size(%__MODULE__{ } = state, options \\ []) when is_list(options) do
    do_action(state, { :size, options }, fn ->
      state.cache
      |> :mnesia.table_info(:size)
      |> Util.ok
    end)
  end

  @doc """
  Returns the internal stats for this worker.
  """
  def stats(%__MODULE__{ } = state, options \\ []) when is_list(options) do
    case Hook.ref_by_module(state.options.post_hooks, Cachex.Stats) do
      nil ->
        { :error, "Stats not enabled for cache with ref '#{state.cache}'" }
      ref ->
        ref
        |> Stats.retrieve(options)
        |> Util.ok
    end
  end

  @doc """
  Removes a key from the cache, returning the last known value for the key.
  """
  def take(%__MODULE__{ } = state, key, options \\ []) when is_list(options) do
    do_action(state, { :take, key, options }, fn ->
      state.actions.take(state, key, options)
    end)
  end

  @doc """
  Executes a transaction of cache actions inside the cache.
  """
  def transaction(%__MODULE__{ } = state, operation, options \\ [])
  when is_function(operation, 1) and is_list(options) do
    Util.handle_transaction(fn ->
      %__MODULE__{ state | actions: __MODULE__.Transactional }
      |> operation.()
      |> Util.ok
    end)
  end

  @doc """
  Returns the time remaining on a key before expiry. The value returned it in
  milliseconds. If the key has no expiration, nil is returned.
  """
  def ttl(%__MODULE__{ } = state, key, options \\ []) when is_list(options) do
    do_action(state, { :ttl, key, options }, fn ->
      state.actions.ttl(state, key, options)
    end)
  end

  ###
  # Behaviours to enforce on all types of workers.
  ###

  @doc """
  Invoked when retrieving a key from the cache. This callback should be implemented
  such that either a key is returned, or a nil value is returned. A status should
  also be provided which is any of `:ok`, `:missing`, or `:loaded` to represent
  how the key was retrieved.
  """
  @callback get(__MODULE__, any, list) :: { :ok | :loaded | :missing, any }
  @callback set(__MODULE__, any, any, list) :: { :ok, true | false }
  @callback update(__MODULE__, any, any, list) :: { :ok, true | false }
  @callback del(__MODULE__, any, list) :: { :ok, true | false }
  @callback clear(__MODULE__, list) :: { :ok, number }
  @callback expire(__MODULE__, any, number, list) :: { :ok, true | false }
  @callback keys(__MODULE__, list) :: { :ok, list }
  @callback incr(__MODULE__, any, list) :: { :ok, number }
  @callback refresh(__MODULE__, any, list) :: { :ok, true | false }
  @callback take(__MODULE__, any, list) :: { :ok | :missing, any }
  @callback ttl(__MODULE__, any, list) :: { :ok | :missing, any }

  ###
  # GenServer delegate functions for call/cast.
  ###

  gen_delegate get(state, key, options), type: :call
  gen_delegate get_and_update(state, key, update_fun, options), type: :call
  gen_delegate set(state, key, value, options), type: [ :call, :cast ]
  gen_delegate update(state, key, value, options), type: [ :call, :cast ]
  gen_delegate del(state, key, options), type: [ :call, :cast ]
  gen_delegate clear(state, options), type: [ :call, :cast ]
  gen_delegate count(state, options), type: :call
  gen_delegate execute(state, operations, options), type: [ :call, :cast ]
  gen_delegate exists?(state, key, options), type: :call
  gen_delegate expire(state, key, expiration, options), type: [ :call, :cast ]
  gen_delegate expire_at(state, key, timestamp, options), type: [ :call, :cast ]
  gen_delegate keys(state, options), type: :call
  gen_delegate incr(state, key, options), type: [ :call, :cast ]
  gen_delegate persist(state, key, options), type: [ :call, :cast ]
  gen_delegate purge(state, options), type: [ :call, :cast ]
  gen_delegate refresh(state, key, options), type: [ :call, :cast ]
  gen_delegate size(state, options), type: :call
  gen_delegate stats(state, options), type: :call
  gen_delegate take(state, key, options), type: :call
  gen_delegate transaction(state, operations, options), type: [ :call, :cast ]
  gen_delegate ttl(state, key, options), type: :call

  ###
  # GenServer manual handlers for call/cast.
  ###

  @doc """
  Very tiny wrapper to retrieve the current state of a cache
  """
  defcall state, do: state

  ###
  # Functions designed to only be used internally (i.e. those not forwarded to
  # the main Cachex interfaces).
  ###

  @doc """
  Forwards a call to the correct actions set, currently only the local actions.
  The idea is that in future this will delegate to distributed implementations,
  so it has been built out in advance to provide a clear migration path.
  """
  def do_action(%__MODULE__{ } = state, message, fun)
  when is_tuple(message) and is_function(fun) do
    case state.options.pre_hooks do
      [] -> nil;
      li -> Notifier.notify(li, message)
    end

    result = fun.()

    case state.options.post_hooks do
      [] -> nil;
      li -> Notifier.notify(li, message, result)
    end

    result
  end

  @doc """
  Retrieves and updates a raw record in the database. This is used in several
  places in order to allow easy modification. The record is fed to an update
  function and the return value is placed in the cache instead. If the record
  does not exist, then nil is passed to the update function.
  """
  def get_and_update_raw(%__MODULE__{ } = state, key, update_fun) when is_function(update_fun) do
    Util.handle_transaction(fn ->
      value = case :mnesia.read(state.cache, key) do
        [{ cache, ^key, touched, ttl, value }] ->
          case Util.has_expired?(touched, ttl) do
            true ->
              :mnesia.delete(state.cache, key, :write)
              { cache, key, Util.now(), nil, nil }
            false ->
              { cache, key, touched, ttl, value }
          end
        _unrecognised_val ->
          { state.cache, key, Util.now(), nil, nil }
      end

      new_value = update_fun.(value)
      :mnesia.write(new_value)
      new_value
    end)
  end

  @doc """
  Carries out a quiet check to determine whether a key exists or not - a quiet
  check is one which does not notify hooks (and so can be used from within other
  actions).
  """
  def quietly_exists?(%__MODULE__{ } = state, key) do
    case :ets.lookup(state.cache, key) do
      [{ _cache, ^key, touched, ttl, _value }] ->
        expired = Util.has_expired?(touched, ttl)
        expired && del(state, key)
        { :ok, !expired }
      _unrecognised_val ->
        { :ok, false }
    end
  end

end
