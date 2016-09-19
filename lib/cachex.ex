defmodule Cachex do
  @moduledoc """
  Cachex provides a straightforward interface for in-memory key/value storage.

  Cachex is an extremely fast, designed for caching but also allowing for more
  general in-memory storage. The main goal of Cachex is achieve a caching implementation
  with a wide array of options, without sacrificing performance. Internally, Cachex
  is backed by ETS and Mnesia, allowing for an easy-to-use interface sitting upon
  extremely well tested tools.

  Cachex comes with support for all of the following (amongst other things):

  - Time-based key expirations
  - Maximum size protection
  - Pre/post execution hooks
  - Statistics gathering
  - Multi-layered caching/key fallbacks
  - Transactions and row locking
  - Asynchronous write operations

  All features are optional to allow you to tune based on the throughput needed.
  See `start_link/3` for further details about how to configure these options and
  example usage.
  """

  # use Macros and Supervisor
  use Cachex.Constants
  use Cachex.Macros
  use Supervisor

  # add some aliases
  alias Cachex.Actions
  alias Cachex.Hook
  alias Cachex.Janitor
  alias Cachex.LockManager
  alias Cachex.Options
  alias Cachex.State
  alias Cachex.Util
  alias Cachex.Util.Names

  # avoid inspect clashes
  import Kernel, except: [ inspect: 2 ]

  # the cache type
  @type cache :: atom | State.t

  # custom options type
  @type options :: [ { atom, any } ]

  # custom status type
  @type status :: :ok | :error | :missing

  @doc """
  Initialize the Mnesia table and supervision tree for this cache, linking the
  cache to the current process.

  We also allow the user to define their own options for the cache. We start a
  Supervisor to look after all internal workers backing the cache, in order to
  make sure everything is fault-tolerant.

  The first argument should be the name (as an atom) of the cache.

  ## Options

    - **ets_opts**

      A list of options to pass to the ETS table initialization.

          iex> Cachex.start_link(:my_cache, [ ets_opts: [ { :write_concurrency, false } ] ])

    - **default_ttl**

      A default expiration time to place on any keys inside the cache (this can be
      overridden when a key is set). This value is in **milliseconds**.

          iex> Cachex.start_link(:my_cache, [ default_ttl: :timer.seconds(1) ])

    - **disable_ode**

      If true, on-demand expiration will be disabled. Keys will only be removed
      by Janitor processes, or by calling `purge/2` directly. Useful in case you
      have a Janitor running and don't want potential deletes to impact your reads.

          iex> Cachex.start_link(:my_cache, [ disable_ode: true ])

    - **fallback**

      A default fallback implementation to use when dealing with multi-layered caches.
      This function is called with a key which has no value, in order to allow loading
      from a different location.

          iex> Cachex.start_link(:my_cache, [ fallback: fn(key) ->
          ...>   generate_value(key)
          ...> end])

    - **fallback_args**

      A list of arguments which can be passed to your fallback functions for multi-layered
      caches. The fallback function receives `[key] ++ args`, so make sure you configure
      your args appropriately. This can be used to pass through things such as clients and
      connections.

          iex> Cachex.start_link(:my_cache, [ fallback_args: [redis_client] ])
          iex> Cachex.get(:my_cache, "key", fallback: fn(key, redis_client) ->
          ...>   redis_client.get(key)
          ...> end)

    - **hooks**

      A list of hooks which will be executed either before or after a Cachex action has
      taken place. These hooks should be instances of Cachex.Hook and implement the hook
      behaviour. An example hook can be found in `Cachex.Stats`.

          iex> hook = %Cachex.Hook{ module: MyHook, type: :post }
          iex> Cachex.start_link(:my_cache, [ hooks: [hook] ])

    - **limit**

      A limit to cap the cache at. This can be an integer or a `Cachex.Limit` structure.

          iex> limit = %Cachex.Limit{ limit: 500, reclaim: 0.1 } # 10%
          iex> Cachex.start_link(:my_cache, [ limit: limit ])

    - **record_stats**

      Whether you wish this cache to record usage statistics or not. This has only minor
      overhead due to being implemented as an asynchronous hook (roughly 1µ/op). Stats
      can be retrieve from a running cache by using `stats/1`.

          iex> Cachex.start_link(:my_cache, [ record_stats: true ])

    - **transactions**

      Whether to have transactions and row locking enabled from cache startup. Please
      note that even if this is false, it will be enable the moment a transaction
      is executed. It's recommended to leave this as the default as it will handle
      most use cases in the most performant way possible.

          iex> Cachex.start_link(:my_cache, [ transactions: true ])

    - **ttl_interval**

      Keys are purged on a schedule (defaults to once a second). This value can be changed
      to customize the schedule that keys are purged on. Be aware that if a key is accessed
      when it *should* have expired, but has not yet been purged, it will be removed at that
      time. The purge runs in a separate process so it doesn't have a negative effect on the
      application, but it may make sense to lower the frequency if you don't have many keys
      expiring at one time. This value is set in **milliseconds**.

          iex> Cachex.start_link(:my_cache, [ ttl_interval: :timer.seconds(5) ])

  """
  @spec start_link(options, options) :: { atom, pid }
  def start_link(cache, options \\ [], server_opts \\ [])
  def start_link(cache, _options, _server_opts) when not is_atom(cache) do
    @error_invalid_name
  end
  def start_link(cache, options, server_opts) do
    with { :ok, true } <- ensure_started,
         { :ok, opts } <- setup_env(cache, options),
         { :ok,  pid }  = Supervisor.start_link(__MODULE__, opts, [ name: cache ] ++ server_opts)
      do
        hlist = Enum.concat(opts.pre_hooks, opts.post_hooks)

        %{ pre: pre, post: post } =
          pid
          |> Supervisor.which_children
          |> link_hooks(hlist)
          |> Hook.group_by_type

        State.update(cache, fn(state) ->
          %State{ state | pre_hooks: pre, post_hooks: post }
        end)

        { :ok, pid }
      end
  end

  @doc """
  Initialize the Mnesia table and supervision tree for this cache, without linking
  the cache to the current process.

  Supports all the same options as `start_link/3`. This is mainly used for testing
  in order to keep caches around when processes may be torn down. You should try
  to avoid using this in production applications and instead opt for a natural
  Supervision tree.
  """
  @spec start(options) :: { atom, pid }
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
  def init(%State{ pre_hooks: pre, post_hooks: post } = state) do
    hook_spec =
      pre
      |> Enum.concat(post)
      |> Enum.map(fn(%Hook{ args: args, module: mod, server_args: opts }) ->
          worker(GenServer, [ mod, args, opts ], [ id: mod ])
         end)

    ttl_workers = if state.ttl_interval do
      [ worker(Janitor, [ state, [ name: state.janitor ] ]) ]
    end

    children = [
      ttl_workers || [],
      [
        worker(LockManager.Server, [ state.cache ])
      ],
      hook_spec
    ]

    State.set(state.cache, state)

    children
    |> Enum.concat
    |> supervise(strategy: :one_for_one)
  end

  @doc """
  Retrieves a value from the cache using a given key.

  ## Options

    * `:fallback` - a fallback function for multi-layered caches, overriding any
      default fallback functions. The value returned by this fallback is placed
      in the cache against the provided key, before being returned to the user.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value")
      iex> Cachex.get(:my_cache, "key")
      { :ok, "value" }

      iex> Cachex.get(:my_cache, "missing_key")
      { :missing, nil }

      iex> Cachex.get(:my_cache, "missing_key", fallback: &String.reverse/1)
      { :loaded, "yek_gnissim" }

  """
  @spec get(cache, any, options) :: { status | :loaded, any }
  defwrap get(cache, key, options \\ []) when is_list(options) do
    do_action(cache, &Actions.Get.execute(&1, key, options))
  end

  @doc """
  Updates a value in the cache, feeding any existing values into an update function.

  This operation is an internal mutation, and as such any set TTL persists - i.e.
  it is not refreshed on this operation.

  ## Options

    * `:fallback` - a fallback function for multi-layered caches, overriding any
      default fallback functions. The value returned by this fallback is passed
      into the update function.

  ## Examples

      iex> Cachex.set(:my_cache, "key", [2])
      iex> Cachex.get_and_update(:my_cache, "key", &([1|&1]))
      { :ok, [1, 2] }

      iex> Cachex.get_and_update(:my_cache, "missing_key", &(["value"|&1]), fallback: &String.reverse/1)
      { :loaded, [ "value", "yek_gnissim" ] }

  """
  @spec get_and_update(cache, any, function, options) :: { status | :loaded, any }
  defwrap get_and_update(cache, key, update_function, options \\ [])
  when is_function(update_function) and is_list(options) do
    do_action(cache, &Actions.GetAndUpdate.execute(&1, key, update_function, options))
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
  @spec set(cache, any, any, options) :: { status, true | false }
  defwrap set(cache, key, value, options \\ []) when is_list(options) do
    do_action(cache, &Actions.Set.execute(&1, key, value, options))
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
  @spec update(cache, any, any, options) :: { status, any }
  defwrap update(cache, key, value, options \\ []) when is_list(options) do
    do_action(cache, &Actions.Update.execute(&1, key, value, options))
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
  @spec del(cache, any, options) :: { status, true | false }
  defwrap del(cache, key, options \\ []) when is_list(options) do
    do_action(cache, &Actions.Del.execute(&1, key, options))
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
  @spec clear(cache, options) :: { status, true | false }
  defwrap clear(cache, options \\ []) when is_list(options) do
    do_action(cache, &Actions.Clear.execute(&1, options))
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
  @spec count(cache, options) :: { status, number }
  defwrap count(cache, options \\ []) when is_list(options) do
    do_action(cache, &Actions.Count.execute(&1, options))
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
  @spec decr(cache, any, options) :: { status, number }
  defwrap decr(cache, key, options \\ []) do
    mod_opts = Keyword.update(options, :amount, -1, &(&1 * -1))
    incr(cache, key, via({ :decr, [ key, options ] }, mod_opts))
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
  @spec empty?(cache, options) :: { status, true | false }
  defwrap empty?(cache, options \\ []) when is_list(options) do
    do_action(cache, fn(cache) ->
      do_action(cache, &Actions.Empty.execute(&1, options))
    end)
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
  @spec execute(cache, function, options) :: { status, any }
  defwrap execute(cache, operation, options \\ [])
  when is_function(operation, 1) and is_list(options) do
    do_action(cache, operation)
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
  @spec exists?(cache, any, options) :: { status, true | false }
  defwrap exists?(cache, key, options \\ []) when is_list(options) do
    do_action(cache, &Actions.Exists.execute(&1, key, options))
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
  @spec expire(cache, any, number, options) :: { status, true | false }
  defwrap expire(cache, key, expiration, options \\ [])
  when (expiration == nil or is_number(expiration)) and is_list(options) do
    do_action(cache, &Actions.Expire.execute(&1, key, expiration, options))
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
  @spec expire_at(cache, binary, number, options) :: { status, true | false }
  defwrap expire_at(cache, key, timestamp, options \\ [])
  when is_number(timestamp) and is_list(options) do
    expire(cache, key, timestamp - Util.now(), via({ :expire_at, [ key, timestamp, options ] }, options))
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
  @spec keys(cache, options) :: [ any ]
  defwrap keys(cache, options \\ []) when is_list(options) do
    do_action(cache, &Actions.Keys.execute(&1, options))
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
  @spec incr(cache, any, options) :: { status, number }
  defwrap incr(cache, key, options \\ []) when is_list(options) do
    do_action(cache, &Actions.Incr.execute(&1, key, options))
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

      iex> Cachex.inspect(:my_cache, { :memory, :bytes })
      { :ok, 10624 }

      iex> Cachex.inspect(:my_cache, :state)
      {:ok,
       %Cachex.State{cache: :my_cache, default_ttl: nil, disable_ode: false,
        ets_opts: [read_concurrency: true, write_concurrency: true], fallback: nil,
        fallback_args: [], janitor: :my_cache_janitor,
        limit: %Cachex.Limit{limit: nil, policy: Cachex.Policy.LRW, reclaim: 0.1},
        manager: :my_cache_manager, post_hooks: [], pre_hooks: [],
        transactions: false, ttl_interval: nil}}

  """
  @spec inspect(cache, atom | tuple) :: { status, any }
  defwrap inspect(cache, option),
  do: do_action(cache, &Actions.Inspect.execute(&1, option))

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
  @spec persist(cache, any, options) :: { status, true | false }
  defwrap persist(cache, key, options \\ []) when is_list(options),
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
  @spec purge(cache, options) :: { status, number }
  defwrap purge(cache, options \\ []) when is_list(options) do
    do_action(cache, &Actions.Purge.execute(&1, options))
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
  @spec refresh(cache, any, options) :: { status, true | false }
  defwrap refresh(cache, key, options \\ []) when is_list(options) do
    do_action(cache, &Actions.Refresh.execute(&1, key, options))
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
  @spec reset(cache, options) :: { status, true }
  defwrap reset(cache, options \\ []) when is_list(options) do
    do_action(cache, &Actions.Reset.execute(&1, options))
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
  @spec size(cache, options) :: { status, number }
  defwrap size(cache, options \\ []) when is_list(options) do
    do_action(cache, &Actions.Size.execute(&1, options))
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
  @spec stats(cache, options) :: { status, %{ } }
  defwrap stats(cache, options \\ []) when is_list(options) do
    do_action(cache, &Actions.Stats.execute(&1, options))
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
  @spec stream(cache, options) :: { status, Enumerable.t }
  defwrap stream(cache, options \\ []) when is_list(options) do
    do_action(cache, &Actions.Stream.execute(&1, options))
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
  @spec take(cache, any, options) :: { status, any }
  defwrap take(cache, key, options \\ []) when is_list(options) do
    do_action(cache, &Actions.Take.execute(&1, key, options))
  end

  @doc """
  Touches the last write time on a key.

  This is similar to `refresh/3` except that TTLs are maintained.
  """
  @spec touch(cache, any, options) :: { status, true | false }
  defwrap touch(cache, key, options \\ []) when is_list(options) do
    do_action(cache, &Actions.Touch.execute(&1, key, options))
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
  @spec transaction(cache, function, options) :: { status, any }
  defwrap transaction(cache, keys, operation, options \\ [])
  when is_function(operation, 1) and is_list(keys) and is_list(options) do
    do_action(cache, fn
      (%State{ cache: cache, transactions: false }) ->
        cache
        |> State.update(&%State{ &1 | transactions: true })
        |> Actions.Transaction.execute(keys, operation, options)
      (state) ->
        Actions.Transaction.execute(state, keys, operation, options)
    end)
  end

  @doc """
  Returns the TTL for a cache entry in milliseconds.

  ## Examples

      iex> Cachex.ttl(:my_cache, "my_key")
      { :ok, 13985 }

      iex> Cachex.ttl(:my_cache, "missing_key")
      { :missing, nil }

  """
  @spec ttl(cache, any, options) :: { status, number }
  defwrap ttl(cache, key, options \\ []) when is_list(options) do
    do_action(cache, &Actions.Ttl.execute(&1, key, options))
  end

  ###
  # Private utility functions.
  ###

  # Executes an action against the given cache. If the cache does not exist, we
  # return an error otherwise we execute the passed in action.
  defp do_action(cache, action) when is_atom(cache) do
    state = State.get(cache)
    where = :erlang.whereis(cache)

    if where != :undefined and state != nil do
      action.(state)
    else
      @error_no_cache
    end
  end
  defp do_action(%State{ } = cache, action),
    do: action.(cache)
  defp do_action(_cache, _action),
    do: @error_no_cache

  # Determines whether the Cachex application state has been started or not. If
  # not, we return an error to tell the user to start it appropriately.
  defp ensure_started do
    State.setup?() && { :ok, true } || @error_not_started
  end

  # Iterates a child spec of a Supervisor and maps the process module names to a
  # list of Hook structs. Wherever there is a match, the PID of the child is added
  # to the Hook so that a Hook struct can track where it lives.
  defp link_hooks(children, hooks) do
    Enum.map(hooks, fn(%Hook{ module: mod } = hook) ->
      pid = Enum.find_value(children, fn
        ({ ^mod, pid, _, _ }) -> pid
        (_) -> nil
      end)

      %Hook{ hook | ref: pid }
   end)
  end

  # Runs through the initial setup for a cache, parsing a list of options into
  # a set of Cachex options, before adding the node to any remote nodes and then
  # setting up the local table. This is separated out as it's required in both
  # `start_link/3` and `start/3`.
  defp setup_env(cache, options) when is_list(options) do
    with { :ok, opts } <- Options.parse(cache, options),
         { :ok, _pid } <- start_table(opts),
     do: { :ok, opts }
  end

  # Starts up an Mnesia table based on the provided options. If an error occurs
  # when setting up the table, we return an error tuple to represent the issue.
  defp start_table(%State{ cache: cache, ets_opts: ets_opts }) do
    Eternal.start_link(cache, ets_opts, [
      name: Names.eternal(cache),
      quiet: true
    ])
  rescue
    _ -> @error_invalid_option
  end

  # Simply adds a "via" param to the options to allow the use of delegates.
  defp via(module, options), do: [ { :via, module } | options ]

end
