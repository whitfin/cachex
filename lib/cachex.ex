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
      { :aborted, { :already_exists, _table } } ->
        nil
      { :aborted, error } ->
        raise error
      _other ->
        :mnesia.add_table_index(parsed_opts.cache, :expiration)
    end

    ttl_workers = case parsed_opts.ttl_interval do
      nil -> []
      _other -> [worker(Cachex.Janitor, [parsed_opts])]
    end

    children = ttl_workers ++ [
      :poolboy.child_spec(parsed_opts.cache, [
        name: {
          :local, parsed_opts.cache
        },
        worker_module: __MODULE__.Worker,
        max_overflow: parsed_opts.overflow,
        size: parsed_opts.workers,
        strategy: :fifo
      ], parsed_opts)
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
    :poolboy.transaction(cache, fn(worker) ->
      GenServer.call(worker, { :get, key }, @def_timeout)
    end)
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
    :poolboy.transaction(cache, fn(worker) ->
      GenServer.call(worker, { :keys })
    end)
  end

  @doc """
  Sets a value in the cache against a given key.

  ## Examples

      iex> Cachex.set(:my_cache, "key", "value")
      { :ok, true }

  """
  @spec set(atom, any, any) :: { status, true | false }
  defcheck set(cache, key, value) do
    :poolboy.transaction(cache, fn(worker) ->
      GenServer.call(worker, { :set, key, value }, @def_timeout)
    end)
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
    :poolboy.transaction(cache, fn(worker) ->
      GenServer.call(worker, { :inc, key, count, initial }, @def_timeout)
    end)
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
    :poolboy.transaction(cache, fn(worker) ->
      GenServer.call(worker, { :delete, key }, @def_timeout)
    end)
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
    :poolboy.transaction(cache, fn(worker) ->
      GenServer.call(worker, { :take, key }, @def_timeout)
    end)
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
    :poolboy.transaction(cache, fn(worker) ->
      GenServer.call(worker, { :clear }, @def_timeout)
    end)
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
    :poolboy.transaction(cache, fn(worker) ->
      GenServer.call(worker, { :empty? }, @def_timeout)
    end)
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
    :poolboy.transaction(cache, fn(worker) ->
      GenServer.call(worker, { :exists?, key }, @def_timeout)
    end)
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
    :poolboy.transaction(cache, fn(worker) ->
      GenServer.call(worker, { :size }, @def_timeout)
    end)
  end

  @doc """
  Retrieves the statistics of a cache.

  ## Examples

      iex> Cachex.stats(:my_cache)
      {:ok,
       %Cachex.Stats{creationDate: 1455418875069, evictionCount: 0, hitCount: 0,
        missCount: 0, opCount: 0, setCount: 0}}

  """
  @spec stats(atom) :: { status, %Cachex.Stats{ } }
  defcheck stats(cache) do
    aggregate(
      cache,
      fn(worker_pid) ->
        GenServer.call(worker_pid, { :stats }, @def_timeout)
      end,
      fn
        (:ok, values) ->
          merged_stats =
            values
            |> Stream.map(&(elem(&1, 1)))
            |> Enum.reduce(%__MODULE__.Stats{ }, &(__MODULE__.Stats.merge/2))

          { :ok, merged_stats }
        (:error, values) ->
          hd(values)
      end
    )
  end

  # Internal aggregator for any functions which need to retrieve a specific
  # set of values from all workers and aggregate them together. An example
  # of this is the `Cachex.stats/1` call, which needs to retrieve per-worker
  # statistics in order to aggregate them together for the full picture.
  defp aggregate(cache, generator_fun, aggregator_fun) do
    total_workers =
      cache
      |> GenServer.call(:get_all_workers)
      |> Enum.count

    values =
      1..total_workers
      |> Enum.reduce([], fn(_iteration, workers) ->
          [:poolboy.checkout(cache)|workers]
         end)
      |> Enum.reduce([], fn(worker_pid, values) ->
          new_value = generator_fun.(worker_pid)
          :poolboy.checkin(cache, worker_pid)
          [new_value|values]
         end)

    values
    |> hd
    |> elem(0)
    |> aggregator_fun.(values)
  end

end
