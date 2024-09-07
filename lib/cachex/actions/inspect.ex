defmodule Cachex.Actions.Inspect do
  @moduledoc false
  # Command module to enable cache inspection.
  #
  # Cache inspection can be anything from checking the current size of the
  # expired keyspace to pulling raw entry records back from the table.
  #
  # Due to the nature of inspection, behaviour in this module can change
  # at any time - not only with major increments of the library version.
  alias Cachex.Query
  alias Cachex.Services
  alias Services.Janitor
  alias Services.Overseer

  # we need macros
  import Cachex.Errors
  import Cachex.Spec

  # define our accepted options for the inspection calls
  @type option ::
          {:expired, :count}
          | {:expired, :keys}
          | {:janitor, :last}
          | {:memory, :bytes}
          | {:memory, :binary}
          | {:memory, :words}
          | {:entry, any}
          | :cache

  # pre-calculated memory size
  @memory_exponent :math.log(1024)

  # internal map of memory suffixes
  @memory_suffixes %{
    0.0 => "B",
    1.0 => "KiB",
    2.0 => "MiB",
    3.0 => "GiB",
    4.0 => "TiB"
  }

  # the number of suffixes stored (not including B)
  @memory_sufcount map_size(@memory_suffixes) - 1.0

  ##############
  # Public API #
  ##############

  @doc """
  Inspect various things about a cache.

  Inspection offers the ability to retrieve pieces of information about a cache
  and the associated services, such as memory use and metadata about internal
  processes.

  There are many options broken up by function head, so please see the source
  commands for definition for further documentation.
  """
  def execute(cache, option, options)

  # Retrieves the internal state of the cache.
  #
  # This is relatively easy to get via other methods, but it's available here
  # as the "best" way for a developer to do so (outside of the internal API).
  def execute(cache(name: name), :cache, _options),
    do: {:ok, Overseer.retrieve(name)}

  # Retrieves a raw entry from the cache table.
  #
  # This is useful when you need access to a record which may have expired. If
  # the entry does not exist, a nil value will be returned instead. Expirations
  # are not taken into account (either lazily or otherwise) on this read call.
  def execute(cache(name: name), {:entry, key}, _options) do
    case :ets.lookup(name, key) do
      [] -> {:ok, nil}
      [e] -> {:ok, e}
    end
  end

  # Returns the number of expired entries currently inside the cache.
  #
  # The number of entries returned represents the number of records which will
  # be removed on the next run of the Janitor service. It does not track the
  # number of expired records which have already been purged or removed.
  def execute(cache(name: name), {:expired, :count}, _options) do
    filter = Query.expired()
    clause = Query.create(where: filter, output: true)

    {:ok, :ets.select_count(name, clause)}
  end

  # Returns the keys of expired entries currently inside the cache.
  #
  # This is essentially the same as the definition above, except that it will
  # return the list of entry keys rather than just a count. Naturally this is
  # an expensive call and should really only be used when debugging.
  def execute(cache(name: name), {:expired, :keys}, _options) do
    filter = Query.expired()
    clause = Query.create(where: filter, output: :key)

    {:ok, :ets.select(name, clause)}
  end

  # Returns information about the last run of the Janitor service.
  #
  # This calls through to the Janitor server, and so might take a while if the
  # server is currently in the process of purging records. The returned metadata
  # schema is defined in the `Cachex.Services.Janitor` module.
  #
  # In the case the Janitor service is not running, an error will be returned.
  def execute(cache() = cache, {:janitor, :last}, _options),
    do: Janitor.last_run(cache)

  # Retrieves the current size of the backing cache table in bytes.
  #
  # This should be treated as an estimation as it's rounded based on
  # the number of words used to maintain the cache.
  def execute(cache() = cache, {:memory, :bytes}, options) do
    {:ok, mem_words} = execute(cache, {:memory, :words}, options)
    {:ok, mem_words * :erlang.system_info(:wordsize)}
  end

  # Retrieves the current size of the backing cache table in a readable format.
  #
  # This should be treated as an estimation as it's rounded based on the number
  # of words used to maintain the cache.
  def execute(cache() = cache, {:memory, :binary}, options) do
    {:ok, bytes} = execute(cache, {:memory, :bytes}, options)
    {:ok, bytes_to_readable(bytes)}
  end

  # Retrieves the current size of the backing cache table in machine words.
  #
  # It's unlikely the caller will want to use this directly, but as it's used
  # by other inspection methods there's no harm in exposing it in the API.
  def execute(cache(name: name), {:memory, :words}, _options),
    do: {:ok, :ets.info(name, :memory)}

  # Catch-all to return an error.
  def execute(_cache, _option, _options),
    do: error(:invalid_option)

  # Converts a number of bytes to a binary representation.
  #
  # Just to avoid confusion, binary here means human readable.
  # We only support up to TiB. Anything over will just group
  # under TiB. For example, a PiB would be `16384.00 TiB`.
  defp bytes_to_readable(bytes) when is_integer(bytes) do
    index =
      bytes
      |> :math.log()
      |> :erlang./(@memory_exponent)
      |> Float.floor()
      |> :erlang.min(@memory_sufcount)

    abbrev = bytes / :math.pow(1024, index)
    suffix = Map.get(@memory_suffixes, index)

    "~.2f ~s"
    |> :io_lib.format([abbrev, suffix])
    |> IO.iodata_to_binary()
  end
end
