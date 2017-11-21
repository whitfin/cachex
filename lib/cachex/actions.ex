defmodule Cachex.Actions do
  @moduledoc false
  # This module contains common actions required to implement cache actions, such
  # as typical CRUD-style operations on records. This module also provides the
  # `defaction` macro which enables the implementation of cache actions without
  # having to manually take care of things such as Hook notifications. This used
  # to be a simple function call (and you would pass the body as an anonymous
  # function), but it makes sense to macro to gain that extra little piece of
  # performance.

  # we need some constants
  use Cachex.Include,
    constants: true,
    models: true

  # add some aliases
  alias Cachex.Cache
  alias Cachex.Services
  alias Cachex.Util

  # alias services
  alias Services.Informant

  @doc """
  This macro provides a base Action template.

  An action is a series of ETS operations which notify any cache Hooks both before
  and after they execute. Rather than have this hand-written or use anonymous
  functions, we provide a macro here. Simply use `defaction` instead of `def`
  in the action declarations and notifications will be handled automatically.

  It should be noted that the function name will be `execute` with the defined
  arity. This is because it makes little sense to do `Cachex.Actions.Ttl.ttl()`
  for example.
  """
  defmacro defaction({ name, _line, [ _cache | stateless_args ] = arguments }, do: body) do
    quote location: :keep do
      def execute(unquote_splicing(arguments)) do
        local_opts  = var!(options)
        local_state = var!(cache)

        notify = Keyword.get(local_opts, :notify, true)

        message = notify && case local_opts[:via] do
          msg when not is_tuple(msg) ->
            { unquote(name), [ unquote_splicing(stateless_args) ] }
          msg ->
            msg
        end

        if notify do
          Informant.broadcast(local_state, message)
        end

        result = (unquote(body))

        if notify do
           results = Keyword.get(local_opts, :hook_result, result)
           Informant.broadcast(local_state, message, results)
        end

        result
      end
    end
  end

  @doc """
  Reads back a key from the cache.

  If the key does not exist we return a `nil` value. If the key has expired, we
  delete it from the cache using the `:purge` action as a notification.
  """
  @spec read(cache :: Cache.t, key :: any) :: Models.entry | nil
  def read(%Cache{ name: name } = cache, key) do
    name
    |> :ets.lookup(key)
    |> handle_read(cache)
  end

  @doc """
  Updates a number of fields in a record inside the cache, by key.

  For ETS, we do this entirely in a single sweep. For Mnesia, we need to use a
  two-step get/update from the Worker interface to accomplish the same. We then
  use a reduction to modify the Tuple.
  """
  @spec update(cache :: Cache.t, key :: any, changes :: [{}]) :: { :ok, true | false }
  def update(%Cache{ name: name }, key, changes) do
    name
    |> :ets.update_element(key, changes)
    |> handle_update
  end

  @doc """
  Writes a record into the cache, and returns a result signifying whether the
  write was successful or not.
  """
  @spec write(cache :: Cache.t, entry :: Models.entry) :: { :ok, true | false }
  def write(%Cache{ name: name }, entry() = entry),
    do: { :ok, :ets.insert(name, entry) }

  # Handles the reesult from a read action in order to handle any expirations
  # set against the key. If the key has expired, we purge it immediately to avoid
  # any issues with consistency. If the record is valid, we just return it as is.
  defp handle_read([ entry(key: key, touched: touched, ttl: ttl) = entry ], cache) do
    if Util.has_expired?(cache, touched, ttl) do
      __MODULE__.Del.execute(cache, key, @purge_override)
      nil
    else
      entry
    end
  end
  defp handle_read(_missing, _cache),
    do: nil

  # Handles an update result, converting a falsey result into a Tuple tagged with
  # the :missing atom. If the result is true, we just return a Tuple tagged with
  # the :ok atom.
  defp handle_update(true),
    do: { :ok, true }
  defp handle_update(false),
    do: { :missing, false }
end
