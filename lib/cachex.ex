defmodule Cachex do
  use Supervisor
  use __MODULE__.Macros

  @moduledoc """
  This module provides simple interactions with a backing memory cache.

  All interactions are simply calls to other processes in order to provide an
  easy-to-scale system. This module acts as an aggregator for the responses from
  workers, no heavy processing happens in here in order to avoid bottlenecks.
  """

  # the default timeout for a GenServer call
  @def_timeout 500

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
  @spec start_link([ { atom, atom } ], [ { atom, atom } ]) :: { atom, pid }
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
  @spec init([ { atom, atom } ]) :: { status, { any } }
  def init(options \\ []) when is_list(options) do
    parsed_opts =
      options
      |> Cachex.Options.parse

    :mnesia.start()

    table_create = :mnesia.create_table(parsed_opts.cache, [
      { :ram_copies, [ node() ] },
      { :attributes, [ :key, :expiration, :value ]},
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
  @spec get(atom, any) :: { status, any }
  defcheck get(cache, key) do
    GenServer.call(cache, { :get, key }, @def_timeout)
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
  @spec keys(atom) :: [ any ]
  defcheck keys(cache) do
    GenServer.call(cache, { :keys })
  end

  @doc """
  Sets a value in the cache against a given key.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value")
      { :ok, true }

  """
  @spec set(atom, any, any) :: { status, true | false }
  defcheck set(cache, key, value) do
    GenServer.call(cache, { :set, key, value }, @def_timeout)
  end

  @doc """
  Increments a key directly in the cache by an amount 1. If the key does
  not exist in the cache, it is set to `0` before being incremented.

  Please note that incrementing a value does not currently refresh any set TTL
  on the key (as the key is still mapped to the same value, the value is simply
  mutated).

  ## Examples

      iex> Cachex.set(:my_cache, "my_key", 1)
      iex> Cachex.inc(:my_cache, "my_key", 1)
      { :ok, 2 }

  """
  @spec inc(atom, any) :: { status, number }
  defcheck inc(cache, key), do: inc(cache, key, 1, 0)

  @doc """
  Increments a key directly in the cache by an amount `count`. If the key does
  not exist in the cache, it is set to `0` before being incremented.

  Please note that incrementing a value does not currently refresh any set TTL
  on the key (as the key is still mapped to the same value, the value is simply
  mutated).

  ## Examples

      iex> Cachex.inc(:my_cache, "missing_key", 1)
      { :ok, 1 }

  """
  @spec inc(atom, any, number) :: { status, number }
  defcheck inc(cache, key, count)
  when is_number(count), do: inc(cache, key, count, 0)

  @doc """
  Increments a key directly in the cache by an amount `count`. If the key does
  not exist in the cache, it is set to `initial` before being incremented.

  Please note that incrementing a value does not currently refresh any set TTL
  on the key (as the key is still mapped to the same value, the value is simply
  mutated).

  ## Examples

      iex> Cachex.inc(:my_cache, "missing_key", 1, 5)
      { :ok, 6 }

  """
  @spec inc(atom, any, number, number) :: { status, number }
  defcheck inc(cache, key, count, initial)
  when is_number(count) and is_number(initial) do
    GenServer.call(cache, { :inc, key, count, initial }, @def_timeout)
  end

  @doc """
  Removes a value from the cache.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value")
      iex> Cachex.get(:my_cache, "key")
      { :ok, "value" }

      iex> Cachex.delete(:my_cache, "key")
      { :ok, true }

      iex> Cachex.get(:my_cache, "key")
      { :ok, nil }

  """
  @spec delete(atom, any) :: { status, true | false }
  defcheck delete(cache, key) do
    GenServer.call(cache, { :delete, key }, @def_timeout)
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
  @spec take(atom, any) :: { status, any }
  defcheck take(cache, key) do
    GenServer.call(cache, { :take, key }, @def_timeout)
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
  @spec clear(atom) :: { status, true | false }
  defcheck clear(cache) do
    GenServer.call(cache, { :clear }, @def_timeout)
  end

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
  @spec empty?(atom) :: { status, true | false }
  defcheck empty?(cache) do
    GenServer.call(cache, { :empty? }, @def_timeout)
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
  @spec exists?(atom, any) :: { status, true | false }
  defcheck exists?(cache, key) do
    GenServer.call(cache, { :exists?, key }, @def_timeout)
  end

  @doc """
  Updates the expiration time on a given cache entry by the value provided.

  ## Examples

      iex> Cachex.expire(:my_cache, 10000)
      {:ok, true}

  """
  @spec expire(atom, binary, number) :: { status, true | false }
  defcheck expire(cache, key, expiration) when is_number(expiration) do
    GenServer.call(cache, { :expire, key, expiration }, @def_timeout)
  end

  @doc """
  Updates the expiration time on a given cache entry to the timestamp provided.

  ## Examples

      iex> Cachex.expire_at(:my_cache, 1455728085502)
      {:ok, true}

  """
  @spec expire_at(atom, binary, number) :: { status, true | false }
  defcheck expire_at(cache, key, timestamp) when is_number(timestamp) do
    GenServer.call(cache, { :expire_at, key, timestamp }, @def_timeout)
  end

  @doc """
  Determines the size of the cache.

  ## Examples

      iex> Cachex.set(:my_cache, "key1", "value1")
      iex> Cachex.set(:my_cache, "key2", "value2")
      iex> Cachex.set(:my_cache, "key3", "value3")
      iex> Cachex.size(:my_cache)
      { :ok, 3 }

  """
  @spec size(atom) :: { status, number }
  defcheck size(cache) do
    GenServer.call(cache, { :size }, @def_timeout)
  end

  @doc """
  Retrieves the statistics of a cache.

  ## Examples

      iex> Cachex.stats(:my_cache)
      {:ok,
       %{creationDate: 1455690638577, evictionCount: 0, expiredCount: 0, hitCount: 0,
         missCount: 0, opCount: 0, requestCount: 0, setCount: 0}}

  """
  @spec stats(atom) :: { status, %{ } }
  defcheck stats(cache) do
    GenServer.call(cache, { :stats }, @def_timeout)
  end

  @doc """
  Returns the TTL for a cache entry in milliseconds.

  If the key is not found, returns an error tuple. If the value is nil, then no
  expiration has been set on the given key.

  ## Examples

      iex> Cachex.ttl(:my_cache, "my_key")
      {:ok, 13985}

  """
  @spec ttl(atom, binary) :: { status, number }
  defcheck ttl(cache, key) do
    GenServer.call(cache, { :ttl, key }, @def_timeout)
  end

end
