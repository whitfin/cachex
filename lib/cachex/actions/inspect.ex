defmodule Cachex.Actions.Inspect do
  @moduledoc false
  # Command module to enable cache inspection.
  #
  # Cache inspection can be anything from checking the current size of the
  # expired keyspace to pulling raw entry records back from the table.
  #
  # Due to the nature of inspection, behaviour in this module can change
  # at any time - not only with major increments of the library version.
  alias Cachex.Services
  alias Cachex.Util
  alias Services.Janitor
  alias Services.Overseer

  # we need macros
  import Cachex.Errors
  import Cachex.Spec

  # define our accepted options for the inspection calls
  @type option :: { :expired, :count } | { :expired, :keys } |
                  { :janitor, :last  } | { :memory, :bytes } |
                  { :memory, :binary } | { :memory, :words } |
                  { :record,     any } |   :cache

  @doc """
  Inspect various things about a cache.

  Inspection offers the ability to retrieve pieces of information about a cache
  and the associated services, such as memory use and metadata about internal
  processes.

  There are many options broken up by function head, so please see the source
  commands for definition for further documentation.
  """
  def execute(cache, option)

  # Returns the number of expired entries currently inside the cache.
  #
  # The number of entries returned represents the number of records which will
  # be removed on the next run of the Janitor service. It does not track the
  # number of expired records which have already been purged or removed.
  def execute(cache(name: name), { :expired, :count }) do
    query = Util.retrieve_expired_rows(true)
    { :ok, :ets.select_count(name, query) }
  end

  # Returns the keys of expired entries currently inside the cache.
  #
  # This is essentially the same as the definition above, except that it will
  # return the list of entry keys rather than just a count. Naturally this is
  # an expensive call and should really only be used when debugging.
  def execute(cache(name: name), { :expired, :keys }) do
    query = Util.retrieve_expired_rows(:key)
    { :ok, :ets.select(name, query) }
  end

  # Returns information about the last run of the Janitor service.
  #
  # This calls through to the Janitor server, and so might take a while if the
  # server is currently in the process of purging records. The returned metadata
  # schema is defined in the `Cachex.Services.Janitor` module.
  #
  # In the case the Janitor service is not running, an error will be returned.
  def execute(cache() = cache, { :janitor, :last }),
    do: Janitor.last_run(cache)

  # Retrieves the current size of the backing cache table in bytes.
  #
  # This should be treated as an estimation as it's rounded based on
  # the number of words used to maintain the cache.
  def execute(cache() = cache, { :memory, :bytes }) do
    { :ok, mem_words } = execute(cache, { :memory, :words })
    { :ok, mem_words * :erlang.system_info(:wordsize) }
  end

  # Retrieves the current size of the backing cache table in a readable format.
  #
  # This should be treated as an estimation as it's rounded based on the number
  # of words used to maintain the cache.
  def execute(cache() = cache, { :memory, :binary }) do
    { :ok, bytes } = execute(cache, { :memory, :bytes })
    { :ok, Util.bytes_to_readable(bytes) }
  end

  # Retrieves the current size of the backing cache table in machine words.
  #
  # It's unlikely the caller will want to use this directly, but as it's used
  # by other inspection methods there's no harm in exposing it in the API.
  def execute(cache(name: name), { :memory, :words }),
    do: { :ok, :ets.info(name, :memory) }

  # Retrieves a raw entry from the cache table.
  #
  # This is useful when you need access to a record which may have expired. If
  # the entry does not exist, a nil value will be returned instead. Expirations
  # are not taken into account (either lazily or otherwise) on this read call.
  def execute(cache(name: name), { :record, key }) do
    case :ets.lookup(name, key) do
      [ ] -> { :ok, nil }
      [e] -> { :ok,   e }
    end
  end

  # Retrieves the internal state of the cache.
  #
  # This is relatively easy to get via other methods, but it's available here
  # as the "best" way for a developer to do so (outside of the internal API).
  def execute(cache(name: name), :cache),
    do: { :ok, Overseer.retrieve(name) }

  # Catch-all to return an error.
  def execute(_cache, _option),
    do: error(:invalid_option)
end
