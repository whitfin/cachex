defmodule Cachex.Worker do
  @moduledoc false
  # The main Worker interface for Cachex, providing access to the backing tables
  # using delegates to implementations for both local and remote caches.

  # add some aliases
  alias Cachex.Hook
  alias Cachex.Janitor
  alias Cachex.Notifier
  alias Cachex.Options
  alias Cachex.State
  alias Cachex.Stats
  alias Cachex.Util

  # define internal struct
  defstruct actions: __MODULE__.Local,  # the actions implementation
            cache: nil,                 # the cache name
            options: %Options{ }        # the options of this cache

  # define the worker state type
  @opaque t :: %__MODULE__{ }

  # define some types
  @type record ::  { atom, any, number, number | nil, any }

  @doc """
  Main initialization phase of a worker, plucking out the options we care about
  and storing them internally for later use by this worker.
  """
  def init(options \\ %Options { }) do
    %__MODULE__{
      actions: options.remote && __MODULE__.Remote || __MODULE__.Local,
      cache: options.cache,
      options: options
    }
  end

  ###
  # Publicly exported functions and operations.
  ###

  @doc """
  Retrieves a value from the cache.
  """
  def get(%__MODULE__{ } = state, key, options \\ []) when is_list(options) do
    do_action(state, { :get, key, options }, fn ->
      case state.actions.read(state, key) do
        { _cache, ^key, _touched, _ttl, value } ->
          { :ok, value }
        _unrecognised_value ->
          fb_fun =
            options
            |> Util.get_opt_function(:fallback)

          case Util.get_fallback(state, key, fb_fun) do
            { :ok, new_value } ->
              { :missing, new_value }
            { :loaded, new_value } = result ->
              set(state, key, new_value)
              result
          end
      end
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

      status = case exists?(state, key, notify: false) do
        { :ok, true } ->
          :ok
        { :ok, false } ->
          case Util.get_fallback_function(state, fb_fun) do
            nil ->
              :missing
            val ->
              has_arity = Util.has_arity?(val, [0, 1, length(state.options.fallback_args) + 1])
              has_arity && :loaded || :missing
          end
      end

      raw_result = get_and_update_raw(state, key, fn({ cache, ^key, touched, ttl, value }) ->
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

      case raw_result do
        { :ok, { _cache, ^key, _touched, _ttl, value } } ->
          { status, value }
        err ->
          err
      end
    end)
  end

  @doc """
  Sets a value in the cache.
  """
  def set(%__MODULE__{ } = state, key, value, options \\ []) when is_list(options) do
    do_action(state, { :set, key, value, options }, fn ->
      ttl =
        options
        |> Util.get_opt_number(:ttl)

      record =
        state
        |> Util.create_record(key, value, ttl)

      state.actions.write(state, record)
    end)
  end

  @doc """
  Updates a value in the cache.
  """
  def update(%__MODULE__{ } = state, key, value, options \\ []) when is_list(options) do
    do_action(state, { :update, key, value, options }, fn ->
      with { :ok, true } <- check_exists(state, key) do
        state.actions.update(state, key, [{ 5, value }])
      end
    end)
  end

  @doc """
  Removes a key from the cache.
  """
  def del(%__MODULE__{ } = state, key, options \\ []) when is_list(options) do
    do_action(state, { :del, key, options }, fn ->
      state.actions.delete(state, key)
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
      case state.actions.read(state, key) do
        { _cache, ^key, _touched, _ttl, _value } ->
          { :ok, true }
        _unrecognised_value ->
          { :ok, false }
      end
    end)
  end

  @doc """
  Refreshes the expiration on a given key based on the value passed in.
  """
  def expire(%__MODULE__{ } = state, key, expiration, options \\ []) when is_list(options) do
    do_action(state, { :expire, key, expiration, options }, fn ->
      with { :ok, true } <- check_exists(state, key) do
        if expiration == nil or expiration > 0 do
          state.actions.update(state, key, [{ 3, Util.now() }, { 4, expiration }])
        else
          del(state, key, via: :purge)
        end
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
      case state.actions.incr(state, key, options) do
        { :error, :non_numeric_value } ->
          { :error, "Unable to operate on non-numeric value" }
        result ->
          result
      end
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
      with { :ok, true } <- check_exists(state, key) do
        state.actions.update(state, key, [{ 3, Util.now() }])
      end
    end)
  end

  @doc """
  Resets a cache and associated hooks.
  """
  def reset(%__MODULE__{ } = state, options \\ []) when is_list(options) do
    only =
      options
      |> Keyword.get(:only, [ :cache, :hooks ])
      |> List.wrap

    state
    |> reset_cache(only, options)
    |> reset_hooks(only, options)

    { :ok, true }
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
  Returns a Stream reprensenting a view of the cache at the current time. There
  are no guarantees that new writes/deletes will be represented in the Stream.
  We're safe to drop to ETS for this as it's purely a read operation.
  """
  def stream(%__MODULE__{ } = state, options \\ []) when is_list(options) do
    do_action(state, { :stream, options }, fn ->
      resource = Stream.resource(
        fn ->
          match_spec =
            options
            |> Keyword.get(:of, { :key, :value })
            |> Util.retrieve_all_rows

          state.cache
          |> :ets.table([ { :traverse, { :select, match_spec } }])
          |> :qlc.cursor
        end,
        fn(cursor) ->
          case :qlc.next_answers(cursor) do
            [] -> { :halt, cursor }
            li -> { li, cursor }
          end
        end,
        &(:qlc.delete_cursor/1)
      )
      { :ok, resource }
    end)
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
      %__MODULE__{ state | actions: __MODULE__.Remote }
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
      case state.actions.read(state, key) do
        { _cache, ^key, _touched, nil, _value } ->
          { :ok, nil }
        { _cache, ^key, touched, ttl, _value } ->
          { :ok, touched + ttl - Util.now() }
        _unrecognised_value ->
          { :missing, nil }
      end
    end)
  end

  ###
  # Behaviours to enforce on all types of workers.
  ###

  # CRUD
  @callback write(__MODULE__, record) :: { :ok, true | false }
  @callback read(__MODULE__, any) :: record | nil
  @callback update(__MODULE__, any, [ { number, any } ]) :: { :ok, true | false }
  @callback delete(__MODULE__, any) :: { :ok, true | false }

  # Bonus
  @callback clear(__MODULE__, list) :: { :ok, number }
  @callback keys(__MODULE__, list) :: { :ok, list }
  @callback incr(__MODULE__, any, list) :: { :ok, number }
  @callback take(__MODULE__, any, list) :: { :ok | :missing, any }

  ###
  # Functions designed to only be used internally (i.e. those not forwarded to
  # the main Cachex interfaces).
  ###

  @doc """
  Handler for adding a node to the worker, to ensure that we use the correct
  actions.
  """
  def add_node(cache, new_node) when is_atom(cache) and is_atom(new_node) do
    if State.member?(cache) do
      State.update(cache, fn(state) ->
        new_options = %Options{ state.options |
          remote: true,
          nodes: if Enum.member?(state.options.nodes, new_node) do
            state.options.nodes
          else
            [new_node|state.options.nodes]
          end
        }

        if state.options.remote do
          %__MODULE__{ state | options: new_options }
        else
          %__MODULE__{ state | actions: __MODULE__.Remote, options: new_options }
        end
      end)
    end
  end

  @doc """
  Handler for broadcasting a set of actions and results to all registered hooks.
  This is fired by out-of-proc calls (i.e. Janitors) which need to notify hooks.
  """
  def broadcast(cache, action, result) when is_atom(cache) do
    case State.get(cache) do
      nil -> false
      val -> do_action(val, action, fn -> result end)
    end
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
          if Util.has_expired?(touched, ttl) do
            :mnesia.delete(state.cache, key, :write)
            { cache, key, Util.now(), nil, nil }
          else
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

  ###
  # Private functions only to be used from inside this module.
  ###

  # Shorthand for doing an internal exists check - normalizing to a missing tuple
  # of { :missing, false } to allow `with` sugar.
  defp check_exists(state, key) do
    with { :ok, false } <- exists?(state, key, notify: false) do
      { :missing, false }
    end
  end

  # Shorthand for joining up the hook list rather than storing it as two separate
  # lists. Used when iterating all hooks.
  defp combine_hooks(%__MODULE__{ options: options }), do: Hook.combine(options)

  # Forwards a call to the correct actions set, currently only the local actions.
  # The idea is that in future this will delegate to distributed implementations,
  # so it has been built out in advance to provide a clear migration path.
  defp do_action(%__MODULE__{ } = state, message, fun)
  when is_tuple(message) and is_function(fun) do
    options =
      message
      |> Util.last_of_tuple

    notify =
      options
      |> Keyword.get(:notify, true)

    message = case options[:via] do
      nil -> message
      val when is_tuple(val) -> val
      val -> put_elem(message, 0, val)
    end

    if notify do
      case state.options.pre_hooks do
        [] -> nil;
        li -> Notifier.notify(li, message)
      end
    end

    result = fun.()

    if notify do
      case state.options.post_hooks do
        [] -> nil;
        li -> Notifier.notify(li, message, options[:hook_result] || result)
      end
    end

    result
  end

  # A small helper for resetting a cache only when defined in the list of items
  # to reset. If the key `:cache` lives inside the list of things to reset, we
  # simply call the internal `clear/2` function with notifications turned off.
  # Otherwise we simply return the state without clearing the cache.
  defp reset_cache(state, only, _opts) do
    if Enum.member?(only, :cache) do
      clear(state, notify: false)
    end
    state
  end

  # Similar to `reset_cache/3`, this helper will reset any required hooks. If
  # the only set determines that we should reset hooks, we check for a list of
  # whitelisted hooks to clear and clear them. If no hook list is provided, we
  # reset all of them. Resetting simply persists of forwarding a reset event to
  # the hook alongside the arguments used to initialize it.
  defp reset_hooks(state, only, opts) do
    if Enum.member?(only, :hooks) do
      state_hooks = combine_hooks(state)

      hooks_list = case Keyword.get(opts, :hooks) do
        nil -> Enum.map(state_hooks, &(&1.module))
        val -> val |> List.wrap
      end

      state_hooks
      |> Enum.filter(&(&1.module in hooks_list))
      |> Enum.each(&(send(&1.ref, { :notify, { :reset, &1.args } })))
    end
    state
  end

end
