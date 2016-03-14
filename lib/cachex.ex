defmodule Cachex do
  # use Macros and Supervisor
  use Cachex.Macros.Boilerplate
  use Supervisor

  # add some aliases
  alias Cachex.Util

  @moduledoc """
  This module provides simple interactions with a backing memory cache.

  All interactions are simply calls to other processes in order to provide an
  easy-to-scale system. This module acts as an aggregator for the responses from
  workers, no heavy processing happens in here in order to avoid bottlenecks.
  """

  # the default timeout for a GenServer call
  @def_timeout 500

  # custom options type
  @type options :: [ { atom, any } ]

  # custom status type
  @type status :: :ok | :error

  @doc """
  Initialize the ETS table for this cache, allowing the user to define their
  own options for the cache.

  We require that we use a named table, so we have to append this value onto
  whatever options they provide. By default, we provided a table which is
  concurrent for both reads and writes, with public access. This can easily be
  modified by the developer.

  ## Options

    **Required:**

    * `:cache_name` - the name of the cache you're creating, non-optional

    **Optional:**

    * `:ets_opts` - a list of options to pass to the ETS table initialization
    * `:table_name` - a name to use alongside the backing ETS table
    * `:workers` - the number of workers to use for this cache, defaults to `1`
    * `:overflow` - a max number of workers to user, defaults to `workers + workers/2`
    * `:default_ttl` - a default expiry time for all new records
    * `:ttl_purge_interval` - how often we should purge expired records
    * `:record_stats` - whether this cache should track usage statistics or not

  ## Examples

      iex> Cachex.start_link([ cache_name: :my_cache, table_name: :test_table ])
      iex> :ets.info(:test_table)[:read_concurrency]
      true

      iex> Cachex.start_link([ cache_name: :my_cache, table_name: :new_test_table, ets_opts: [ { :read_concurrency, false } ]])
      iex> :ets.info(:new_test_table)[:read_concurrency]
      false

  """
  @spec start_link(options, options) :: { atom, pid }
  def start_link(options \\ [], supervisor_options \\ []) do
    Supervisor.start_link(__MODULE__, options, supervisor_options)
  end

  @doc """
  The initialization phase of being set up using a Supervisor.

  This function will set up a poolboy instance for this cache, allowing for
  pooling access to the backing GenServer - this avoids a single GenServer
  becoming a bottleneck. There's a slight overhead involved if you only care
  about a single worker, but it keeps it nice and straightforward in the code.
  """
  @spec init(options) :: { status, { any } }
  def init(options \\ []) when is_list(options) do
    parsed_opts =
      options
      |> Cachex.Options.parse

    :mnesia.start()

    table_create = :mnesia.create_table(parsed_opts.cache, [
      { :ram_copies, [ node() ] },
      { :attributes, [ :key, :touched, :ttl, :value ]},
      { :type, :set },
      { :storage_properties, [ { :ets, parsed_opts.ets_opts } ] }
    ])

    case table_create do
      { :aborted, { :already_exists, _table } } -> nil
      { :aborted, error } ->
        raise error
      _other -> nil
    end

    ttl_workers = case parsed_opts.ttl_interval do
      nil -> []
      _other -> [worker(Cachex.Janitor, [parsed_opts])]
    end

    children = ttl_workers ++ [
      worker(Cachex.Worker, [parsed_opts, [name: parsed_opts.cache]])
    ]

    supervise(children, strategy: :one_for_one)
  end

  @doc """
  Retrieves a value from the cache.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value")
      iex> Cachex.get(:my_cache, "key")
      { :ok, "value" }

      iex> Cachex.get(:my_cache, "missing_key")
      { :ok, nil }

  """
  @spec get(atom, any, options) :: { status, any }
  defcheck get(cache, key, options \\ []) when is_list(options) do
    GenServer.call(cache, { :get, key, options }, @def_timeout)
  end

  @doc """
  Retrieves a value from the cache.

  ## Examples

      iex> Cachex.set(:my_cache, "key", [2])
      iex> Cachex.get_and_update(:my_cache, &([1|&1]))
      { :ok, [1, 2] }

  """
  @spec get_and_update(atom, any, function, options) :: { status, any }
  defcheck get_and_update(cache, key, update_function, options \\ [])
  when is_function(update_function) and is_list(options) do
    GenServer.call(cache, { :get_and_update, key, update_function, options }, @def_timeout)
  end

  @doc """
  Sets a value in the cache against a given key.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value")
      { :ok, true }

  """
  @spec set(atom, any, any, options) :: { status, true | false }
  defcheck set(cache, key, value, options \\ []) when is_list(options) do
    handle_async(cache, { :set, key, value, options }, options)
  end

  @doc """
  Removes a value from the cache.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value")
      iex> Cachex.get(:my_cache, "key")
      { :ok, "value" }

      iex> Cachex.del(:my_cache, "key")
      { :ok, true }

      iex> Cachex.get(:my_cache, "key")
      { :ok, nil }

  """
  @spec del(atom, any, options) :: { status, true | false }
  defcheck del(cache, key, options \\ []) when is_list(options) do
    handle_async(cache, { :del, key, options }, options)
  end

  @doc """
  Removes all items in the cache.

  ## Examples

      iex> Cachex.set(:my_cache, "key1", "value1")
      iex> Cachex.set(:my_cache, "key2", "value2")
      iex> Cachex.set(:my_cache, "key3", "value3")
      iex> Cachex.size(:my_cache)
      { :ok, 3 }

      iex> Cachex.clear(:my_cache)
      { :ok, true }

      iex> Cachex.size(:my_cache)
      { :ok, 0 }

  """
  @spec clear(atom, options) :: { status, true | false }
  defcheck clear(cache, options \\ []) when is_list(options) do
    handle_async(cache, { :clear, options }, options)
  end

  @doc """
  Determines the size of the cache. Unlike `size/1`, this ignores keys which
  should have expired. Naturally there is a cost to this.

  ## Examples

      iex> Cachex.set(:my_cache, "key1", "value1")
      iex> Cachex.set(:my_cache, "key2", "value2")
      iex> Cachex.set(:my_cache, "key3", "value3")
      iex> Cachex.length(:my_cache)
      { :ok, 3 }

  """
  @spec count(atom, options) :: { status, number }
  defcheck count(cache, options \\ []) when is_list(options) do
    GenServer.call(cache, { :count, options }, @def_timeout)
  end

  @doc """
  Decrements a key directly in the cache by an amount `count`. If the key does
  not exist in the cache, it is set to `initial` before being decremented.

  Please note that decrementing a value does not currently refresh any set TTL
  on the key (as the key is still mapped to the same value, the value is simply
  mutated).

  ## Examples

      iex> Cachex.set(:my_cache, "my_key", 10)
      iex> Cachex.decr(:my_cache, "my_key")
      { :ok, 9 }

      iex> Cachex.set(:my_cache, "my_new_key", 10)
      iex> Cachex.decr(:my_cache, "my_new_key", 5)
      { :ok, 5 }

      iex> Cachex.decr(:my_cache, "missing_key", 10, 5)
      { :ok, 5 }

  """
  @spec decr(atom, any, number, options) :: { status, number }
  defcheck decr(cache, key, amount \\ 1, options \\ []),
  do: incr(cache, key, amount * -1, options)

  @doc """
  Checks whether the cache is empty.

  ## Examples

      iex> Cachex.set(:my_cache, "key1", "value1")
      iex> Cachex.set(:my_cache, "key2", "value2")
      iex> Cachex.set(:my_cache, "key3", "value3")
      iex> Cachex.empty?(:my_cache)
      { :ok, false }

      iex> Cachex.clear(:my_cache)
      { :ok, true }

      iex> Cachex.empty?(:my_cache)
      { :ok, true }

  """
  @spec empty?(atom, options) :: { status, true | false }
  defcheck empty?(cache, options \\ []) when is_list(options) do
    case size(cache) do
      { :ok, size } -> { :ok, size == 0 }
      _other_value_ -> { :ok, false }
    end
  end

  @doc """
  Determines whether a given key exists inside the cache.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value")
      iex> Cachex.exists?(:my_cache, "key")
      { :ok, true }

      iex> Cachex.exists?(:my_cache, "missing_key")
      { :ok, false }

  """
  @spec exists?(atom, any, options) :: { status, true | false }
  defcheck exists?(cache, key, options \\ []) when is_list(options) do
    GenServer.call(cache, { :exists?, key, options }, @def_timeout)
  end

  @doc """
  Updates the expiration time on a given cache entry by the value provided.

  ## Examples

      iex> Cachex.expire(:my_cache, 10000)
      {:ok, true}

  """
  @spec expire(atom, binary, number, options) :: { status, true | false }
  defcheck expire(cache, key, expiration, options \\ [])
  when is_number(expiration) and is_list(options) do
    handle_async(cache, { :expire, key, expiration, options }, options)
  end

  @doc """
  Updates the expiration time on a given cache entry to the timestamp provided.

  ## Examples

      iex> Cachex.expire_at(:my_cache, 1455728085502)
      {:ok, true}

  """
  @spec expire_at(atom, binary, number, options) :: { status, true | false }
  defcheck expire_at(cache, key, timestamp, options \\ [])
  when is_number(timestamp) and is_list(options) do
    handle_async(cache, { :expire_at, key, timestamp, options }, options)
  end

  @doc """
  Retrieves all keys from the cache, and returns them as an (unordered) list.

  ## Examples

      iex> Cachex.set(:my_cache, "key1", "value1")
      iex> Cachex.set(:my_cache, "key2", "value2")
      iex> Cachex.set(:my_cache, "key3", "value3")
      iex> Cachex.keys(:my_cache)
      { :ok, [ "key2", "key1", "key3" ] }

      iex> Cachex.keys(:empty_cache)
      { :ok, [] }

  """
  @spec keys(atom, options) :: [ any ]
  defcheck keys(cache, options \\ []) when is_list(options) do
    GenServer.call(cache, { :keys, options }, @def_timeout)
  end

  @doc """
  Increments a key directly in the cache by an amount `count`. If the key does
  not exist in the cache, it is set to `initial` before being incremented.

  Please note that incrementing a value does not currently refresh any set TTL
  on the key (as the key is still mapped to the same value, the value is simply
  mutated).

  ## Examples

      iex> Cachex.set(:my_cache, "my_key", 1)
      iex> Cachex.incr(:my_cache, "my_key")
      { :ok, 2 }

      iex> Cachex.set(:my_cache, "my_new_key", 1)
      iex> Cachex.incr(:my_cache, "my_new_key", 2)
      { :ok, 3 }

      iex> Cachex.incr(:my_cache, "missing_key", 1, 5)
      { :ok, 6 }

  """
  @spec incr(atom, any, options) :: { status, number }
  defcheck incr(cache, key, amount \\ 1, options \\ []) when is_list(options) do
    handle_async(cache, { :incr, key, amount, options }, options)
  end

  @doc """
  Removes a TTL on a given document.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value", 1000)
      iex> Cachex.ttl(:my_cache, "key")
      { :ok, 1000 }

      iex> Cachex.persist(:my_cache, "key")
      { :ok, true }

  """
  @spec persist(atom, any, options) :: { status, true | false }
  defcheck persist(cache, key, options \\ []) when is_list(options) do
    handle_async(cache, { :persist, key, options }, options)
  end

  @doc """
  Triggers a TTL based eviction loop, running in the calling process rather than
  in the TTL handler. This can be used to implement custom eviction policies.

  ## Examples

      iex> Cachex.purge(:my_cache)
      {:ok, 15}

  """
  @spec purge(atom, options) :: { status, number }
  defcheck purge(cache, options \\ []) when is_list(options) do
    handle_async(cache, { :purge, options }, options)
  end


  @doc """
  Refreshes the TTL for the provided key. This will reset the TTL to begin from
  the current time.

  ## Examples

      iex> Cachex.ttl(:my_cache, "my_key")
      {:ok, 13985}

      iex> Cachex.refresh(:my_cache, "my_key")
      {:ok, true}

      iex> Cachex.ttl(:my_cache, "my_key")
      {:ok, 20000}

  """
  @spec refresh(atom, binary, options) :: { status, true | false }
  defcheck refresh(cache, key, options \\ []) when is_list(options) do
    handle_async(cache, { :refresh, key, options }, options)
  end

  @doc """
  Determines the size of the cache. This includes any expired but unevicted keys.
  For a more accurate representation, use `count/1`.

  ## Examples

      iex> Cachex.set(:my_cache, "key1", "value1")
      iex> Cachex.set(:my_cache, "key2", "value2")
      iex> Cachex.set(:my_cache, "key3", "value3")
      iex> Cachex.size(:my_cache)
      { :ok, 3 }

  """
  @spec size(atom, options) :: { status, number }
  defcheck size(cache, options \\ []) when is_list(options) do
    GenServer.call(cache, { :size, options }, @def_timeout)
  end

  @doc """
  Retrieves the statistics of a cache.

  ## Examples

      iex> Cachex.stats(:my_cache)
      {:ok,
       %{creationDate: 1455690638577, evictionCount: 0, expiredCount: 0, hitCount: 0,
         missCount: 0, opCount: 0, requestCount: 0, setCount: 0}}

  """
  @spec stats(atom, options) :: { status, %{ } }
  defcheck stats(cache, options \\ []) when is_list(options) do
    GenServer.call(cache, { :stats, options }, @def_timeout)
  end

  @doc """
  Takes a key from the cache, whilst also removing it from the cache.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value")
      iex> Cachex.take(:my_cache, "key")
      { :ok, "value" }

      iex> Cachex.get(:my_cache, "key")
      { :ok, nil }

      iex> Cachex.take(:my_cache, "missing_key")
      { :ok, nil }

  """
  @spec take(atom, any, options) :: { status, any }
  defcheck take(cache, key, options \\ []) when is_list(options) do
    GenServer.call(cache, { :take, key, options }, @def_timeout)
  end

  @doc """
  Returns the TTL for a cache entry in milliseconds.

  If the key is not found, returns an error tuple. If the value is nil, then no
  expiration has been set on the given key.

  ## Examples

      iex> Cachex.ttl(:my_cache, "my_key")
      {:ok, 13985}

  """
  @spec ttl(atom, binary, options) :: { status, number }
  defcheck ttl(cache, key, options \\ []) when is_list(options) do
    GenServer.call(cache, { :ttl, key, options }, @def_timeout)
  end

  # Internal function to handle async delegation. This is just a wrapper around
  # the call/cast functions inside the GenServer module.
  defp handle_async(cache, args, options) do
    if options[:async] do
      cache
      |> GenServer.cast(args)
      |> (&(&1 && Util.ok(true) || Util.error(false))).()
    else
      GenServer.call(cache, args, @def_timeout)
    end
  end

end
