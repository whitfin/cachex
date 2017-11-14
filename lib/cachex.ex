defmodule Cachex do
  @moduledoc """
  Cachex provides a straightforward interface for in-memory key/value storage.

  Cachex is an extremely fast, designed for caching but also allowing for more
  general in-memory storage. The main goal of Cachex is achieve a caching
  implementation with a wide array of options, without sacrificing performance.
  Internally, Cachex is backed by ETS, allowing for an easy-to-use interface
  sitting upon extremely well tested tools.

  Cachex comes with support for all of the following (amongst other things):

  - Time-based key expirations
  - Maximum size protection
  - Pre/post execution hooks
  - Statistics gathering
  - Multi-layered caching/key fallbacks
  - Transactions and row locking
  - Asynchronous write operations
  - Syncing to a local filesystem
  - User command invocation

  All features are optional to allow you to tune based on the throughput needed.
  See `start_link/3` for further details about how to configure these options and
  example usage.
  """

  # add all use clauses
  use Cachex.Constants
  use Supervisor

  # allow unsafe generation
  use Unsafe.Generator,
    handler: :unwrap_unsafe

  # add some aliases
  alias Cachex.Actions
  alias Cachex.Errors
  alias Cachex.ExecutionError
  alias Cachex.Options
  alias Cachex.Services
  alias Cachex.State
  alias Cachex.Util

  # alias any services
  alias Services.Informant

  # import util macros
  require Cachex.State

  # avoid inspect clashes
  import Kernel, except: [ inspect: 2 ]

  # the cache type
  @type cache :: atom | State.t

  # custom status type
  @type status :: :ok | :error | :missing

  # generate unsafe definitions
  @unsafe [
    clear:          [ 1, 2 ],
    count:          [ 1, 2 ],
    decr:           [ 2, 3 ],
    del:            [ 2, 3 ],
    dump:           [ 2, 3 ],
    empty?:         [ 1, 2 ],
    execute:        [ 2, 3 ],
    exists?:        [ 2, 3 ],
    expire:         [ 3, 4 ],
    expire_at:      [ 3, 4 ],
    fetch:          [ 3, 4 ],
    get:            [ 2, 3 ],
    get_and_update: [ 3, 4 ],
    incr:           [ 2, 3 ],
    inspect:           [ 2 ],
    invoke:         [ 3, 4 ],
    keys:           [ 1, 2 ],
    load:           [ 2, 3 ],
    persist:        [ 2, 3 ],
    purge:          [ 1, 2 ],
    refresh:        [ 2, 3 ],
    reset:          [ 1, 2 ],
    set:            [ 3, 4 ],
    size:           [ 1, 2 ],
    stats:          [ 1, 2 ],
    stream:         [ 1, 2 ],
    take:           [ 2, 3 ],
    touch:          [ 2, 3 ],
    transaction:    [ 3, 4 ],
    ttl:            [ 2, 3 ],
    update:         [ 3, 4 ]
  ]

  @doc """
  Initialize the Mnesia table and supervision tree for this cache, linking the
  cache to the current process.

  We also allow the user to define their own options for the cache. We start a
  Supervisor to look after all internal workers backing the cache, in order to
  make sure everything is fault-tolerant.

  The first argument should be the name (as an atom) of the cache.

  ## Options

    * `:commands` - A custom set of commands to attach to the cache in order to
      provide shorthand execution. A cache command must be of the form
      `{ :return | :modify, fn/1 }` and adhere to these rules:

      </br>
      - If you use `:return`, the return value of your command will simply be the
        return value of your call to `:invoke` - very straightforward and easy.
      - If you use `:modify`, your command must return a two-element Tuple, with
        the first element being the return value of your command, and the second
        being the modified value to write back into the cache. Anything that
        doesn't fit this will cause an error intentionally (there's no way to
        rescue this).

      </br>
      Cache commands are set on a per-cache basis (for now), and can only be set
      at cache start (though this may change).

          iex> Cachex.start_link(:my_cache, [
          ...>   commands: [
          ...>     last: { :return, &List.last/1 },
          ...>     trim: { :modify, &String.trim/1 }
          ...>   ]
          ...> ])
          { :ok, _pid }

    * `:default_ttl` - A default expiration time to place on any keys inside the
      cache (this can be overridden when a key is set). This value is in **milliseconds**.

          iex> Cachex.start_link(:my_cache, [ default_ttl: :timer.seconds(1) ])

    * `:ets_opts` - A list of options to pass to the ETS table initialization.

          iex> Cachex.start_link(:my_cache, [ ets_opts: [ { :write_concurrency, false } ] ])

    * `:fallback` - A default fallback implementation to use when dealing with
      multi-layered caches. This function is called with a key which has no value,
      in order to allow loading from a different location.
      </br></br>
      You should tag the return value inside a `:commit` Tuple, to signal that you
      wish to commit the changes to the cache. If you *don't* want to commit the
      changes (for example if something goes wrong), you can use `{ :ignore, val }`
      to only return the value and not persist it. If you don't specify either of
      these flags, it will be assumed you are committing your changes.
      </br></br>
      You can also provide a state to your fallback by passing a List of options
      rather than just a function. Using the `:state` key will provide your state
      value as the second argument any time it is called. Any state which is set
      to `nil` will not be provided as the second argument. Even if a default
      fallback function is not set, you may still set a state - the state will
      still be provided to any fallbacks which are command-specific.
      </br></br>
      When providing option syntax you should use the `:action` key to provide
      your function. Should you prefer you can use this syntax even when you
      don't need a state, simply by providing `[ action: function ]`. This is the
      internal behaviour used when a simple function is provided anyway.

          iex> Cachex.start_link(:my_cache, [
          ...>   fallback: fn(key) ->
          ...>     { :commit, generate_value(key) }
          ...>   end
          ...> ])
          { :ok, _pid1 }

          iex> Cachex.start_link(:my_cache, [
          ...>   fallback: [
          ...>     state: my_state,
          ...>     action: fn(key, state) ->
          ...>       { :commit, generate_value(key) }
          ...>     end
          ...>   ]
          ...> ])
          { :ok, _pid2 }

    * `:hooks` - A list of hooks which will be executed either before or after a
      Cachex action has taken place. These hooks should be instances of `Cachex.Hook`
      and implement the hook behaviour. An example hook can be found in `Cachex.Stats`.

          iex> hook = %Cachex.Hook{ module: MyHook, type: :post }
          iex> Cachex.start_link(:my_cache, [ hooks: [hook] ])

    * `:limit` - A limit to cap the cache at. This can be an integer or a `Cachex.Limit`
      structure.

          iex> limit = %Cachex.Limit{ limit: 500, reclaim: 0.1 } # 10%
          iex> Cachex.start_link(:my_cache, [ limit: limit ])

    * `:ode` -  If false, on-demand expiration will be disabled. Keys will
      only be removed by Janitor processes, or by calling `purge/2` directly. Useful
      in case you have a Janitor running and don't want potential deletes to impact
      your reads. Defaults to `true`.

          iex> Cachex.start_link(:my_cache, [ ode: false ])

    * `:record_stats` - Whether you wish this cache to record usage statistics or
      not. This has only minor overhead due to being implemented as an asynchronous
      hook (roughly 1µ/op). Stats can be retrieve from a running cache by using
      `Cachex.stats/2`.

          iex> Cachex.start_link(:my_cache, [ record_stats: true ])

    * `:transactions` - Whether to have transactions and row locking enabled from
      cache startup. Please note that even if this is false, it will be enabled
      the moment a transaction is executed. It's recommended to leave this as the
      default as it will handle most use cases in the most performant way possible.

          iex> Cachex.start_link(:my_cache, [ transactions: true ])

    * `:ttl_interval` - An interval to dicate how often to purge expired keys.
      This value can be changed to customize the schedule that keys are purged on.
      Be aware that if a key is accessed when it *should* have expired, but has
      not yet been purged, it will be removed at that time.
      </br></br>
      The purge runs in a separate process so it doesn't have a negative effect
      on the application, but it may make sense to lower the frequency if you don't
      have many keys expiring at one time. This value is set in **milliseconds**.

          iex> Cachex.start_link(:my_cache, [ ttl_interval: :timer.seconds(5) ])

  """
  @spec start_link(atom, Keyword.t, Keyword.t) :: { atom, pid }
  def start_link(cache, options \\ [], server_opts \\ [])
  def start_link(cache, _options, _server_opts) when not is_atom(cache),
    do: @error_invalid_name
  def start_link(cache, options, server_opts) do
    with { :ok,  true } <- ensure_started(),
         { :ok,  true } <- ensure_unused(cache),
         { :ok, state } <- setup_env(cache, options),
         { :ok,   pid }  = Supervisor.start_link(__MODULE__, state, [ name: cache ] ++ server_opts),
         { :ok,  link }  = Informant.link(state),
                ^link   <- State.update(cache, link),
     do: { :ok,   pid }
  end

  @doc """
  Initialize the Mnesia table and supervision tree for this cache, without linking
  the cache to the current process.

  Supports all the same options as `start_link/3`. This is mainly used for testing
  in order to keep caches around when processes may be torn down. You should try
  to avoid using this in production applications and instead opt for a natural
  Supervision tree.
  """
  @spec start(atom, Keyword.t, Keyword.t) :: { atom, pid }
  def start(cache, options \\ [], server_opts \\ []) do
    with { :ok, pid } <- start_link(cache, options, server_opts) do
      :erlang.unlink(pid) && { :ok, pid }
    end
  end

  @doc false
  # Basic initialization phase, being passed arguments by the Supervisor.
  #
  # This function sets up the Mnesia table and options are parsed before being used
  # to setup the internal workers. Workers are then given to `supervise/2`.
  @spec init(state :: State.t) :: { status, any }
  def init(%State{ } = state) do
    state
    |> Services.cache_spec
    |> supervise(strategy: :one_for_one)
  end

  @doc """
  Retrieves a value from the cache using a given key.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value")
      iex> Cachex.get(:my_cache, "key")
      { :ok, "value" }

      iex> Cachex.get(:my_cache, "missing_key")
      { :missing, nil }

  """
  @spec get(cache, any, Keyword.t) :: { status | :loaded, any }
  def get(cache, key, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Get.execute(state, key, options)
    end
  end

  @doc """
  Updates a value in the cache, feeding any existing values into an update function.

  This operation is an internal mutation, and as such any set TTL persists - i.e.
  it is not refreshed on this operation.

  This function accepts the same return syntax as fallback functions, in that if
  you return a Tuple of the form `{ :ignore, value }`, the value is returned from
  the call but is not written to the cache. You can use this to abandon writes
  which began eagerly (for example if a key is actually missing).

  ## Examples

      iex> Cachex.set(:my_cache, "key", [2])
      iex> Cachex.get_and_update(:my_cache, "key", &([1|&1]))
      { :ok, [1, 2] }

      iex> Cachex.get_and_update(:my_cache, "missing_key", fn
      ...>   (nil) -> { :ignore, nil }
      ...>   (val) -> { :commit, [ "value" | val ] }
      ...> end)
      { :missing, nil }

  """
  @spec get_and_update(cache, any, function, Keyword.t) :: { status | :loaded, any }
  def get_and_update(cache, key, update_function, options \\ [])
  when is_function(update_function) and is_list(options) do
    State.enforce(cache, state) do
      Actions.GetAndUpdate.execute(state, key, update_function, options)
    end
  end

  @doc """
  Sets a value in the cache against a given key.

  This will overwrite any value that was previously set against the provided key,
  and overwrite any TTLs which were already set.

  ## Options

    * `:ttl` - a time-to-live for the provided key/value pair, overriding any
      default ttl. This value should be in milliseconds.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value")
      { :ok, true }

      iex> Cachex.set(:my_cache, "key", "value", async: true)
      { :ok, true }

      iex> Cachex.set(:my_cache, "key", "value", ttl: :timer.seconds(5))
      { :ok, true }

  """
  @spec set(cache, any, any, Keyword.t) :: { status, true | false }
  def set(cache, key, value, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Set.execute(state, key, value, options)
    end
  end

  @doc """
  Updates a value in the cache. Unlike `get_and_update/4`, this does a blind
  overwrite.

  This operation is an internal mutation, and as such any set TTL persists - i.e.
  it is not refreshed on this operation.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value")
      iex> Cachex.get(:my_cache, "key")
      { :ok, "value" }

      iex> Cachex.update(:my_cache, "key", "new_value")
      iex> Cachex.get(:my_cache, "key")
      { :ok, "new_value" }

      iex> Cachex.update(:my_cache, "key", "final_value", async: true)
      iex> Cachex.get(:my_cache, "key")
      { :ok, "final_value" }

      iex> Cachex.update(:my_cache, "missing_key", "new_value")
      { :missing, false }

  """
  @spec update(cache, any, any, Keyword.t) :: { status, any }
  def update(cache, key, value, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Update.execute(state, key, value, options)
    end
  end

  @doc """
  Removes a value from the cache.

  This will return `{ :ok, true }` regardless of whether a key has been removed
  or not. The `true` value can be thought of as "is value is no longer present?".

  ## Examples

      iex> Cachex.del(:my_cache, "key")
      { :ok, true }

      iex> Cachex.del(:my_cache, "key", async: true)
      { :ok, true }

  """
  @spec del(cache, any, Keyword.t) :: { status, true | false }
  def del(cache, key, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Del.execute(state, key, options)
    end
  end

  @doc """
  Removes all key/value pairs from the cache.

  This function returns a tuple containing the total number of keys removed from
  the internal cache. This is equivalent to running `size/2` before running `clear/2`.

  ## Examples

      iex> Cachex.set(:my_cache, "key1", "value1")
      iex> Cachex.clear(:my_cache)
      { :ok, 1 }

      iex> Cachex.set(:my_cache, "key1", "value1")
      iex> Cachex.clear(:my_cache, async: true)
      { :ok, true }

  """
  @spec clear(cache, Keyword.t) :: { status, true | false }
  def clear(cache, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Clear.execute(state, options)
    end
  end

  @doc """
  Determines the current size of the unexpired keyspace.

  Unlike `size/2`, this ignores keys which should have expired. Due to this taking
  potentially expired keys into account, it is far more expensive than simply
  calling `size/2` and should only be used when completely necessary.

  ## Examples

      iex> Cachex.set(:my_cache, "key1", "value1")
      iex> Cachex.set(:my_cache, "key2", "value2")
      iex> Cachex.set(:my_cache, "key3", "value3")
      iex> Cachex.count(:my_cache)
      { :ok, 3 }

  """
  @spec count(cache, Keyword.t) :: { status, number }
  def count(cache, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Count.execute(state, options)
    end
  end

  @doc """
  Decrements a key directly in the cache.

  This operation is an internal mutation, and as such any set TTL persists - i.e.
  it is not refreshed on this operation.

  ## Options

    * `:amount` - an amount to decrement by. This will default to 1.
    * `:initial` - if the key does not exist, it will be initialized to this amount.
      Defaults to 0.

  ## Examples

      iex> Cachex.set(:my_cache, "my_key", 10)
      iex> Cachex.decr(:my_cache, "my_key")
      { :ok, 9 }

      iex> Cachex.decr(:my_cache, "my_key", async: true)
      { :ok, true }

      iex> Cachex.set(:my_cache, "my_new_key", 10)
      iex> Cachex.decr(:my_cache, "my_new_key", amount: 5)
      { :ok, 5 }

      iex> Cachex.decr(:my_cache, "missing_key", amount: 5, initial: 0)
      { :missing, -5 }

  """
  @spec decr(cache, any, Keyword.t) :: { status, number }
  def decr(cache, key, options \\ []) do
    mod_opts = Keyword.update(options, :amount, -1, &(&1 * -1))
    incr(cache, key, via({ :decr, [ key, options ] }, mod_opts))
  end

  @doc """
  Writes a cache to a location on disk.

  This operation will flush the current state to the provided disk location, with
  any issues being returned to the user. This dump can be loaded back into a new
  cache instance in the future.

  ## Options

    * `:compression` - a level of compression to apply to the backup (0-9). This
      will default to 1, which is typically appropriate for most backups. Using
      0 will disable compression completely at a cost of higher disk space.

  ## Examples

      iex> Cachex.set(:my_cache, "my_key", 10)
      iex> Cachex.dump(:my_cache, "/tmp/my_default_backup")
      { :ok, true }

      iex> Cachex.dump(:my_cache, "/tmp/my_custom_backup", [ compressed: 0 ])
      { :ok, true }

  """
  @spec dump(cache, binary, Keyword.t) :: { status, any }
  def dump(cache, path, options \\ [])
  when is_binary(path) and is_list(options) do
    State.enforce(cache, state) do
      Actions.Dump.execute(state, path, options)
    end
  end

  @doc """
  Checks whether the cache is empty.

  This operates based on keys living in the cache, regardless of whether they should
  have expired previously or not. Internally this is just sugar for checking if
  `size/2` returns 0.

  ## Examples

      iex> Cachex.set(:my_cache, "key1", "value1")
      iex> Cachex.empty?(:my_cache)
      { :ok, false }

      iex> Cachex.clear(:my_cache)
      { :ok, 1 }

      iex> Cachex.empty?(:my_cache)
      { :ok, true }

  """
  @spec empty?(cache, Keyword.t) :: { status, true | false }
  def empty?(cache, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Empty.execute(state, options)
    end
  end

  @doc """
  Executes a function in the context of a cache worker. This can be used when
  carrying out several operations at once to avoid the jumps between processes.

  However this does **not** provide a transactional execution (i.e. no rollbacks),
  it's simply to avoid the overhead of jumping between processes. For a transactional
  implementation, see `transaction/3`.

  You **must** use the worker instance passed to the provided function when calling
  the cache, otherwise this function will provide no benefits.

  ## Examples

      iex> Cachex.set(:my_cache, "key1", "value1")
      iex> Cachex.set(:my_cache, "key2", "value2")
      iex> Cachex.execute(:my_cache, fn(worker) ->
      ...>   val1 = Cachex.get!(worker, "key1")
      ...>   val2 = Cachex.get!(worker, "key2")
      ...>   [val1, val2]
      ...> end)
      { :ok, [ "value1", "value2" ] }

  """
  @spec execute(cache, function, Keyword.t) :: { status, any }
  def execute(cache, operation, options \\ [])
  when is_function(operation, 1) and is_list(options) do
    State.enforce(cache, state) do
      operation.(state)
    end
  end

  @doc """
  Determines whether a given key exists inside the cache.

  This only determines if the key lives in the keyspace of the cache. Note that
  this determines existence within the bounds of TTLs; this means that if a key
  doesn't "exist", it may still be occupying memory in the cache.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value")
      iex> Cachex.exists?(:my_cache, "key")
      { :ok, true }

      iex> Cachex.exists?(:my_cache, "missing_key")
      { :ok, false }

  """
  @spec exists?(cache, any, Keyword.t) :: { status, true | false }
  def exists?(cache, key, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Exists.execute(state, key, options)
    end
  end

  @doc """
  Sets a TTL on a key in the cache in milliseconds.

  The following rules apply:

  - If the key does not exist in the cache, you will receive a result indicating
    this.
  - If the value provided is `nil`, the TTL is removed.
  - If the value is less than `0`, the key is immediately evicted.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value")
      iex> Cachex.expire(:my_cache, "key", :timer.seconds(5))
      { :ok, true }

      iex> Cachex.expire(:my_cache, "missing_key", :timer.seconds(5))
      { :missing, false }

      iex> Cachex.expire(:my_cache, "key", :timer.seconds(5), async: true)
      { :ok, true }

      iex> Cachex.expire(:my_cache, "missing_key", :timer.seconds(5), async: true)
      { :ok, true }

  """
  @spec expire(cache, any, number, Keyword.t) :: { status, true | false }
  def expire(cache, key, expiration, options \\ [])
  when (expiration == nil or is_number(expiration)) and is_list(options) do
    State.enforce(cache, state) do
      Actions.Expire.execute(state, key, expiration, options)
    end
  end

  @doc """
  Updates the expiration time on a given cache entry to expire at the time provided.

  If the key does not exist in the cache, you will receive a result indicating
  this. If the expiration date is in the past, the key will be immediately evicted
  when this function is called.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value")
      iex> Cachex.expire_at(:my_cache, "key", 1455728085502)
      { :ok, true }

      iex> Cachex.expire_at(:my_cache, "missing_key", 1455728085502)
      { :missing, false }

      iex> Cachex.expire_at(:my_cache, "key", 1455728085502, async: true)
      { :ok, true }

      iex> Cachex.expire_at(:my_cache, "missing_key", 1455728085502, async: true)
      { :ok, true }

  """
  @spec expire_at(cache, binary, number, Keyword.t) :: { status, true | false }
  def expire_at(cache, key, timestamp, options \\ [])
  when is_number(timestamp) and is_list(options) do
    via_opts = via({ :expire_at, [ key, timestamp, options ] }, options)
    expire(cache, key, timestamp - Util.now(), via_opts)
  end

  @doc """
  Fetches a value from the cache, executing the fallback on cache miss.

  If the fallback is executed, the return value will be placed in the cache. You
  should use a return value of `{ :ignore, value }` to avoid writing to the cache.
  This can be used to abandon writes if required.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value")
      iex> Cachex.fetch(:my_cache, "key", fn(key) ->
      ...>   { :commit, String.reverse(key) }
      ...> end)
      { :ok, "value" }

      iex> Cachex.fetch(:my_cache, "missing_key", fn(key) ->
      ...>   { :ignore, String.reverse(key) }
      ...> end)
      { :ignore, "yek_gnissim" }

      iex> Cachex.fetch(:my_cache, "missing_key", fn(key) ->
      ...>   { :commit, String.reverse(key) }
      ...> end)
      { :commit, "yek_gnissim" }

  """
  @spec fetch(cache, any, function, Keyword.t) :: { status | :commit | :ignore, any }
  def fetch(cache, key, fallback, options \\ [])
  when is_function(fallback) and is_list(options) do
    State.enforce(cache, state) do
      Actions.Fetch.execute(state, key, fallback, options)
    end
  end

  @doc """
  Retrieves all keys from the cache, and returns them as an (unordered) list.

  ## Examples

      iex> Cachex.set(:my_cache, "key1", "value1")
      iex> Cachex.set(:my_cache, "key2", "value2")
      iex> Cachex.set(:my_cache, "key3", "value3")
      iex> Cachex.keys(:my_cache)
      { :ok, [ "key2", "key1", "key3" ] }

      iex> Cachex.clear(:my_cache)
      iex> Cachex.keys(:my_cache)
      { :ok, [] }

  """
  @spec keys(cache, Keyword.t) :: { status, [ any ] }
  def keys(cache, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Keys.execute(state, options)
    end
  end

  @doc """
  Increments a key directly in the cache.

  This operation is an internal mutation, and as such any set TTL persists - i.e.
  it is not refreshed on this operation.

  ## Options

    * `:amount` - an amount to increment by. This will default to 1.
    * `:initial` - if the key does not exist, it will be initialized to this amount
      before being modified. Defaults to 0.

  ## Examples

      iex> Cachex.set(:my_cache, "my_key", 10)
      iex> Cachex.incr(:my_cache, "my_key")
      { :ok, 11 }

      iex> Cachex.incr(:my_cache, "my_key", async: true)
      { :ok, true }

      iex> Cachex.set(:my_cache, "my_new_key", 10)
      iex> Cachex.incr(:my_cache, "my_new_key", amount: 5)
      { :ok, 15 }

      iex> Cachex.incr(:my_cache, "missing_key", amount: 5, initial: 0)
      { :missing, 5 }

  """
  @spec incr(cache, any, Keyword.t) :: { status, number }
  def incr(cache, key, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Incr.execute(state, key, options)
    end
  end

  @doc """
  Various debug operations for a cache.

  These operations typically happen outside of the worker process (i.e. in the
  calling process). As such they have no impact on the actions being taken by the
  worker. This means that these operations are safe for use with hot caches, but
  come with a stricter set of limitations.

  Accepted options are only provided for convenience and should not be relied upon.
  They are not part of the public interface (despite being documented) and as such
  may be removed at any time (however this does not mean that they will be).

  Please use cautiously. `inspect/2` is provided mainly for testing purposes and
  so performance isn't as much of a concern.

  ## Options

    * `{ :expired, :count }` - the number of keys which have expired but have not
      yet been removed by TTL handlers.
    * `{ :expired, :keys }` - the list of unordered keys which have expired but
      have not yet been removed by TTL handlers.
    * `{ :janitor, :last }` - returns various information about the last run of
      a Janitor process.
    * `{ :memory, :bytes }` - the memory footprint of the cache in bytes.
    * `{ :memory, :binary }` - the memory footprint of the cache in binary format.
    * `{ :memory, :words }` - the memory footprint of the cache as a number of
      Erlang words.
    * `{ :record, key }` - the raw record of a key inside the cache.
    * `:state` - the internal state of the cache.

  ## Examples

      iex> Cachex.inspect(:my_cache, { :expired, :count })
      { :ok, 0 }

      iex> Cachex.inspect(:my_cache, { :expired, :keys })
      { :ok, [ ] }

      iex> Cachex.inspect(:my_cache, { :janitor, :last })
      { :ok, %{ count: 0, duration: 57, started: 1475476530925 } }

      iex> Cachex.inspect(:my_cache, { :memory, :binary })
      { :ok, "10.38 KiB" }

      iex> Cachex.inspect(:my_cache, { :memory, :bytes })
      { :ok, 10624 }

      iex> Cachex.inspect(:my_cache, { :memory, :words })
      { :ok, 1328 }

      iex> Cachex.inspect(:my_cache, { :record, "my_key" } )
      { :ok, { "my_key", 1475476615662, 1, "my_value" } }

      iex> Cachex.inspect(:my_cache, :state)
      {:ok,
       %Cachex.State{cache: :my_cache, commands: %{}, default_ttl: nil,
        ets_opts: [read_concurrency: true, write_concurrency: true],
        fallback: %Cachex.Fallback{action: nil, state: nil},
        janitor: :my_cache_janitor,
        limit: %Cachex.Limit{limit: nil, policy: Cachex.Policy.LRW, reclaim: 0.1},
        manager: :my_cache_manager, ode: true, post_hooks: [], pre_hooks: [],
        transactions: false, ttl_interval: nil}}

  """
  @spec inspect(cache, atom | tuple) :: { status, any }
  def inspect(cache, option) do
    State.enforce(cache, state) do
      Actions.Inspect.execute(state, option)
    end
  end

  @doc """
  Invokes a custom command against a key inside a cache.

  The chosen command must be a valid command as defined in the `start_link/3`
  call when setting up your cache. The return value of this function depends
  almost entirely on the return value of your command, but with `{ :ok, _res }`
  syntax.

  ## Examples

      iex> Cachex.start_link(:my_cache, [ commands: [ last: { :return, &List.last/1 } ] ])
      iex> Cachex.set(:my_cache, "my_list", [ 1, 2, 3 ])
      iex> Cachex.invoke(:my_cache, "my_list", :last)
      { :ok, 3 }

  """
  @spec invoke(cache, any, atom, Keyword.t) :: any
  def invoke(cache, key, cmd, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Invoke.execute(state, key, cmd, options)
    end
  end

  @doc """
  Loads a cache backup file from a location on disk.

  This operation will only succeed if a valid backup file is provided, otherwise
  an error will be returned.

  ## Examples

      iex> Cachex.set(:my_cache, "my_key", 10)
      iex> Cachex.dump(:my_cache, "/tmp/my_backup")
      iex> Cachex.clear(:my_cache)
      iex> Cachex.load(:my_cache, "/tmp/my_backup")
      { :ok, true }

  """
  @spec load(cache, binary, Keyword.t) :: { status, any }
  def load(cache, path, options \\ [])
  when is_binary(path) and is_list(options) do
    State.enforce(cache, state) do
      Actions.Load.execute(state, path, options)
    end
  end

  @doc """
  Removes a TTL on a given document.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value", ttl: 1000)
      iex> Cachex.persist(:my_cache, "key")
      { :ok, true }

      iex> Cachex.persist(:my_cache, "missing_key")
      { :missing, false }

      iex> Cachex.persist(:my_cache, "missing_key", async: true)
      { :ok, true }

  """
  @spec persist(cache, any, Keyword.t) :: { status, true | false }
  def persist(cache, key, options \\ []) when is_list(options),
  do: expire(cache, key, nil, via({ :persist, [ key, options ] }, options))

  @doc """
  Triggers a mass deletion of all expired keys.

  This can be used to implement custom eviction policies rather than relying on
  the internal policy. Be careful though, calling `purge/2` manually will result
  in the purge firing inside the main process rather than inside the TTL worker.

  ## Examples

      iex> Cachex.purge(:my_cache)
      { :ok, 15 }

      iex> Cachex.purge(:my_cache, async: true)
      { :ok, true }

  """
  @spec purge(cache, Keyword.t) :: { status, number }
  def purge(cache, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Purge.execute(state, options)
    end
  end

  @doc """
  Refreshes the TTL for the provided key. This will reset the TTL to begin from
  the current time.

  ## Examples

      iex> Cachex.set(:my_cache, "my_key", "my_value", ttl: :timer.seconds(5))
      iex> :timer.sleep(4)
      iex> Cachex.refresh(:my_cache, "my_key")
      iex> Cachex.ttl(:my_cache, "my_key")
      { :ok, 5000 }

      iex> Cachex.refresh(:my_cache, "missing_key")
      { :missing, false }

      iex> Cachex.refresh(:my_cache, "my_key", async: true)
      { :ok, true }

      iex> Cachex.refresh(:my_cache, "missing_key", async: true)
      { :ok, true }

  """
  @spec refresh(cache, any, Keyword.t) :: { status, true | false }
  def refresh(cache, key, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Refresh.execute(state, key, options)
    end
  end

  @doc """
  Resets a cache by clearing the keyspace and restarting any hooks.

  ## Options

    * `:hooks` - a whitelist of hooks to reset. Defaults to all hooks.
    * `:only` - a whitelist of components to clear. Currently this can only be
      either of `:cache` or `:hooks`. Defaults to `[ :cache, :hooks ]`.

  ## Examples

      iex> Cachex.set(:my_cache, "my_key", "my_value")
      iex> Cachex.reset(:my_cache)
      iex> Cachex.size(:my_cache)
      { :ok, 0 }

      iex> Cachex.reset(:my_cache, [ only: :hooks ])
      { :ok, true }

      iex> Cachex.reset(:my_cache, [ only: :hooks, hooks: [ MyHook ] ])
      { :ok, true }

      iex> Cachex.reset(:my_cache, [ only: :cache ])
      { :ok, true }

  """
  @spec reset(cache, Keyword.t) :: { status, true }
  def reset(cache, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Reset.execute(state, options)
    end
  end

  @doc """
  Determines the total size of the cache.

  This includes any expired but unevicted keys. For a more representation which
  doesn't include expired keys, use `count/2`.

  ## Examples

      iex> Cachex.set(:my_cache, "key1", "value1")
      iex> Cachex.set(:my_cache, "key2", "value2")
      iex> Cachex.set(:my_cache, "key3", "value3")
      iex> Cachex.size(:my_cache)
      { :ok, 3 }

  """
  @spec size(cache, Keyword.t) :: { status, number }
  def size(cache, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Size.execute(state, options)
    end
  end

  @doc """
  Retrieves the statistics of a cache.

  If statistics gathering is not enabled, an error is returned.

  ## Options

    * `:for` - a specific set of actions to retrieve statistics for.

  ## Examples

      iex> Cachex.stats(:my_cache)
      {:ok, %{creationDate: 1460312824198, missCount: 1, opCount: 2, setCount: 1}}

      iex> Cachex.stats(:my_cache, for: :get)
      {:ok, %{creationDate: 1460312824198, get: %{missing: 1}}}

      iex> Cachex.stats(:my_cache, for: :raw)
      {:ok,
       %{get: %{missing: 1}, global: %{missCount: 1, opCount: 2, setCount: 1},
         meta: %{creationDate: 1460312824198}, set: %{true: 1}}}

      iex> Cachex.stats(:my_cache, for: [ :get, :set ])
      {:ok, %{creationDate: 1460312824198, get: %{missing: 1}, set: %{true: 1}}}

      iex> Cachex.stats(:cache_with_no_stats)
      { :error, :stats_disabled }

  """
  @spec stats(cache, Keyword.t) :: { status, %{ } }
  def stats(cache, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Stats.execute(state, options)
    end
  end

  @doc """
  Returns a Stream which can be used to iterate through a cache.

  This operates entirely on an ETS level in order to provide a moving view of the
  cache. As such, if you wish to operate on any keys as a result of this Stream,
  please buffer them up and execute using `transaction/3`.

  ## Options

    * `:of` - allows you to return a stream of a custom format, however usually
      only `:key` or `:value` will be needed. This can be an atom or a tuple and
      defaults to using `{ :key, :value }` if unset.

  ## Examples

      iex> Cachex.set(:my_cache, "a", 1)
      iex> Cachex.set(:my_cache, "b", 2)
      iex> Cachex.set(:my_cache, "c", 3)
      {:ok, true}

      iex> :my_cache |> Cachex.stream! |> Enum.to_list
      [{"b", 2}, {"c", 3}, {"a", 1}]

      iex> :my_cache |> Cachex.stream!(of: :key) |> Enum.to_list
      ["b", "c", "a"]

      iex> :my_cache |> Cachex.stream!(of: :value) |> Enum.to_list
      [2, 3, 1]

      iex> :my_cache |> Cachex.stream!(of: { :key, :ttl }) |> Enum.to_list
      [{"b", nil}, {"c", nil}, {"a", nil}]

  """
  @spec stream(cache, Keyword.t) :: { status, Enumerable.t }
  def stream(cache, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Stream.execute(state, options)
    end
  end

  @doc """
  Takes a key from the cache.

  This is equivalent to running `get/3` followed by `del/3` in a single action.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value")
      iex> Cachex.take(:my_cache, "key")
      { :ok, "value" }

      iex> Cachex.get(:my_cache, "key")
      { :missing, nil }

      iex> Cachex.take(:my_cache, "missing_key")
      { :missing, nil }

  """
  @spec take(cache, any, Keyword.t) :: { status, any }
  def take(cache, key, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Take.execute(state, key, options)
    end
  end

  @doc """
  Touches the last write time on a key.

  This is similar to `refresh/3` except that TTLs are maintained.
  """
  @spec touch(cache, any, Keyword.t) :: { status, true | false }
  def touch(cache, key, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Touch.execute(state, key, options)
    end
  end

  @doc """
  Transactional equivalent of `execute/3`.

  You **must** use the worker instance passed to the provided function when calling
  the cache, otherwise your request will time out. This is due to the blocking
  nature of the execution, and can not be avoided (at this time).

  ## Examples

      iex> Cachex.set(:my_cache, "key1", "value1")
      iex> Cachex.set(:my_cache, "key2", "value2")
      iex> Cachex.transaction(:my_cache, fn(worker) ->
      ...>   val1 = Cachex.get(worker, "key1")
      ...>   val2 = Cachex.get(worker, "key2")
      ...>   [val1, val2]
      ...> end)
      { :ok, [ "value1", "value2" ] }

      iex> Cachex.transaction(:my_cache, fn(worker) ->
      ...>   Cachex.set(worker, "key3", "value3")
      ...>   Cachex.abort(:exit_early)
      ...> end)
      { :error, :exit_early }

      iex> Cachex.get(:my_cache, "key3")
      { :missing, nil }

  """
  @spec transaction(cache, [ any ], function, Keyword.t) :: { status, any }
  def transaction(cache, keys, operation, options \\ [])
  when is_function(operation, 1) and is_list(keys) and is_list(options) do
    State.enforce(cache, state) do
      if state.transactions do
        Actions.Transaction.execute(state, keys, operation, options)
      else
        cache
        |> State.update(&%State{ &1 | transactions: true })
        |> Actions.Transaction.execute(keys, operation, options)
      end
    end
  end

  @doc """
  Returns the TTL for a cache entry in milliseconds.

  ## Examples

      iex> Cachex.ttl(:my_cache, "my_key")
      { :ok, 13985 }

      iex> Cachex.ttl(:my_cache, "missing_key")
      { :missing, nil }

  """
  @spec ttl(cache, any, Keyword.t) :: { status, number }
  def ttl(cache, key, options \\ []) when is_list(options) do
    State.enforce(cache, state) do
      Actions.Ttl.execute(state, key, options)
    end
  end

  ###
  # Private utility functions.
  ###

  # Determines whether the Cachex application state has been started or not. If
  # not, we return an error to tell the user to start it appropriately.
  defp ensure_started do
    if State.setup?() do
      { :ok, true }
    else
      @error_not_started
    end
  end

  # Ensures that the designated cache name is not currently in use. To determine
  # this we check to see if the name is in use by an existing GenServer.
  defp ensure_unused(cache) do
    case GenServer.whereis(cache) do
      nil -> { :ok, true }
      pid -> { :error, { :already_started, pid } }
    end
  end

  # Runs through the initial setup for a cache, parsing a list of options into
  # a set of Cachex options, We then try to create a base ETS table to ensure
  # that all options are valid, remove it, and report back that everything is
  # ready to go. This cannot be done later, as Eternal is started in the tree -
  # meaning that the Supervisor would crash and restart rather than returning
  # an error message explaining what had happened.
  defp setup_env(cache, options) when is_list(options) do
    with { :ok, opts } <- Options.parse(cache, options) do
      try do
        :ets.new(cache, [ :named_table | opts.ets_opts ])
        :ets.delete(cache)
        { :ok, opts }
      rescue
        _ -> @error_invalid_option
      end
    end
  end

  # Unwraps a result coming back from a cache function to raise any errors as
  # required, or return the raw value being represented. This is never called
  # directly but rather passed through to the :unsafe library to generate bang
  # functions at compile time and then route proxy results through to here.
  defp unwrap_unsafe({ :error, value }) when is_atom(value),
    do: raise ExecutionError, message: Errors.long_form(value)
  defp unwrap_unsafe({ :error, value }) when is_binary(value),
    do: raise ExecutionError, message: value
  defp unwrap_unsafe({ _state, value }),
    do: value

  # Simply adds a "via" param to the options to allow the use of delegates.
  defp via(module, options),
    do: [ { :via, module } | options ]
end
