defmodule Cachex.Actions.Inspect do
  @moduledoc false
  # This module contains inspection tools for a cache. Cache inspection can be
  # anything from checking the current expired keyspace, to pulling the raw doc
  # back from the cache. Options are defined in function heads to make the module
  # easier to follow for newcomers.

  # we need constants
  use Cachex.Constants

  # add any aliases
  alias Cachex.State
  alias Cachex.Util

  # save the inspect function
  import Kernel, except: [ inspect: 2 ]

  # define our accepted options
  @type option :: { :expired, :count } | { :expired, :keys } |
                  { :janitor, :last  } | { :memory, :bytes } |
                  { :memory, :binary } | { :memory, :words } |
                  { :record,     any } |   :state

  @doc """
  Inspect various things about a cache.

  This action offers the ability to retrieve various pieces of information about
  a cache, such as memory and metadata about internal processes. There are many
  options so we call a private function named `inspect/2`, and each option is
  documented individually.
  """
  def execute(state, option), do: inspect(state, option)

  # Returns the number of expired documents which currently live inside the cache
  # (i.e. those which will be removed if a Janitor purge executes). We do this
  # with a simple count query using the utils to generate the query easily.
  defp inspect(%State{ cache: cache }, { :expired, :count }) do
    query = Util.retrieve_expired_rows(true)
    { :ok, :ets.select_count(cache, query) }
  end

  # Returns the keys of expired documents which currently live inside the cache
  # (i.e. those which will be removed if a Janitor purge executes). This is very
  # expensive if there are a lot of keys expired, so use wisely.
  defp inspect(%State{ cache: cache }, { :expired, :keys }) do
    query = Util.retrieve_expired_rows(:key)
    { :ok, :ets.select(cache, query) }
  end

  # Returns information about the last run of a Janitor process (if there is one).
  # We make sure to try validate the existence of the Janitor before calling it,
  # but a crash here shouldn't really be an issue (as it's used for debugging).
  #
  # If the Janitor doesn't exist, an error is returned to inform the user, otherwise
  # we just return the metadata in an ok Tuple.
  defp inspect(%State{ janitor: ref }, { :janitor, :last }) do
    if :erlang.whereis(ref) != :undefined do
      { :ok, GenServer.call(ref, :last) }
    else
      @error_janitor_disabled
    end
  end

  # Retrieves the current size of the underlying ETS table backing the cache and
  # returns it as a number of bytes after using the system word size for the
  # calculation.
  defp inspect(%State{ } = state, { :memory, :bytes }) do
    { :ok, mem_words } = inspect(state, { :memory, :words })
    { :ok, mem_words * :erlang.system_info(:wordsize) }
  end

  # Retrieves the current size of the underlying ETS table backing the cache and
  # returns it as a human readable binary representation. This uses the inspect
  # action to calculate the byte count of a cache under the hood.
  defp inspect(%State{ } = state, { :memory, :binary }) do
    { :ok, bytes } = inspect(state, { :memory, :bytes })
    { :ok, Util.bytes_to_readable(bytes) }
  end

  # Retrieves the current word count of the underlying ETS table backing the cache
  # and returns it in an ok Tuple. It is unlikely the user will ever need this,
  # but the other memory inspections use it so it doesn't hurt to expose it anyway.
  defp inspect(%State{ cache: cache }, { :memory, :words }) do
    { :ok, :ets.info(cache, :memory) }
  end

  # Retrieves a raw record from the cache, specified by the provided key. This
  # is useful when you need access to a record which may have expired. If the
  # record doesn't exist, a nil value will be returned instead.
  defp inspect(%State{ cache: cache }, { :record, key }) do
    case :ets.lookup(cache, key) do
      [ ] -> { :ok, nil }
      [r] -> { :ok,   r }
    end
  end

  # Simply returns the current state of the cache. This is easy enough to get
  # through other methods, but it's available here to refer to as the "best"
  # way for a consumer to do so (someone who isn't developing Cachex).
  defp inspect(%State{ cache: cache }, :state) do
    { :ok, State.get(cache) }
  end

  # This is just a catch all to tell the user they asked for an invalid option.
  defp inspect(_cache, _option), do: @error_invalid_option

end
