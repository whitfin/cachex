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

  ## Examples

      iex> Cachex.start_link([ cache_name: :my_cache, table_name: :test_table ])
      iex> :ets.info(:test_table)[:read_concurrency]
      true

      iex> Cachex.start_link([ cache_name: :my_cache, table_name: :new_test_table, ets_opts: [ { :read_concurrency, false } ]])
      iex> :ets.info(:new_test_table)[:read_concurrency]
      false

  """
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
  def init(options \\ []) when is_list(options) do
    cache_name = case options[:cache_name] do
      val when val == nil or not is_atom(val) ->
        raise "Cache name must be a valid atom!"
      val -> val
    end

    ets_opts = Keyword.get(options, :ets_opts, [
      { :read_concurrency, true },
      { :write_concurrency, true },
      :public,
      :set
    ])

    table_name = case options[:table_name] do
      val when val == nil or val == false or not is_atom(val) ->
        :ets.new(options[:table_name], ets_opts)
      val ->
        :ets.new(val, ets_opts ++ [:named_table])
    end

    names = [
      cache: cache_name,
      table: table_name
    ]

    overflow = case options[:overflow] do
      val when not is_number(val) or val < 1 -> nil
      val -> val
    end

    workers = case options[:workers] do
      nil -> 1
      val when not is_number(val) -> 1
      val -> val
    end

    children = [
      :poolboy.child_spec(cache_name, [
        name: {
          :local, cache_name
        },
        worker_module: __MODULE__.Worker,
        max_overflow: (overflow || workers + div(workers, 2)),
        size: workers,
        strategy: :fifo
      ], options ++ names)
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
  deft get(cache, key) do
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
  deft keys(cache) do
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
  deft set(cache, key, value) do
    :poolboy.transaction(cache, fn(worker) ->
      GenServer.call(worker, { :set, key, value }, @def_timeout)
    end)
  end

  @doc """
  Increments a key directly in the cache by an amount 1. If the key does
  not exist in the cache, it is set to `0` before being incremented.

  ## Examples

      iex> Cachex.set(:my_cache, "my_key", 1)
      iex> Cachex.inc(:my_cache, "my_key", 1)
      { :ok, 2 }

  """
  deft inc(cache, key), do: inc(cache, key, 1, 0)

  @doc """
  Increments a key directly in the cache by an amount `count`. If the key does
  not exist in the cache, it is set to `0` before being incremented.

  ## Examples

      iex> Cachex.inc(:my_cache, "missing_key", 1)
      { :ok, 1 }

  """
  deft inc(cache, key, count)
  when is_number(count), do: inc(cache, key, count, 0)

  @doc """
  Increments a key directly in the cache by an amount `count`. If the key does
  not exist in the cache, it is set to `initial` before being incremented.

  ## Examples

      iex> Cachex.inc(:my_cache, "missing_key", 1, 5)
      { :ok, 6 }

  """
  deft inc(cache, key, count, initial)
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
  deft delete(cache, key) do
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
  deft take(cache, key) do
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
  deft clear(cache) do
    :poolboy.transaction(cache, fn(worker) ->
      GenServer.call(worker, { :clear }, @def_timeout)
    end)
  end

  @doc """
  Returns information about the backing ETS table.

  ## Examples

      iex> Cachex.info(:my_cache)
      {:ok,
       [read_concurrency: true, write_concurrency: true, compressed: false,
        memory: 1361, owner: #PID<0.126.0>, heir: :none, name: :my_cache, size: 2,
        node: :nonode@nohost, named_table: true, type: :set, keypos: 1,
        protection: :public]}

  """
  deft info(cache) do
    :poolboy.transaction(cache, fn(worker) ->
      GenServer.call(worker, { :info }, @def_timeout)
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
  deft empty?(cache) do
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
  deft exists?(cache, key) do
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
  deft size(cache) do
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
  deft stats(cache) do
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
