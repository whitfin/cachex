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
  use Cachex.Constants

  # add some aliases
  alias Cachex.Hook
  alias Cachex.State
  alias Cachex.Util

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
  defmacro defaction({ name, _line, [ _state | stateless_args ] = arguments }, do: body) do
    quote do
      def execute(unquote_splicing(arguments)) do
        local_opts  = var!(options)
        local_state = var!(state)

        notify = Keyword.get(local_opts, :notify, true)

        message = notify && case local_opts[:via] do
          msg when not is_tuple(msg) ->
            { unquote(name), [ unquote_splicing(stateless_args) ] }
          msg ->
            msg
        end

        notify && Hook.notify(local_state.pre_hooks, message, nil)

        result = (unquote(body))

        if notify do
           results = Keyword.get(local_opts, :hook_result, result)
           Hook.notify(local_state.post_hooks, message, results)
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
  @spec read(state :: State.t, key :: any) :: Record.t | nil
  def read(%{ cache: cache } = state, key) do
    cache
    |> :ets.lookup(key)
    |> handle_read(state)
  end

  @doc """
  Updates a number of fields in a record inside the cache, by key.

  For ETS, we do this entirely in a single sweep. For Mnesia, we need to use a
  two-step get/update from the Worker interface to accomplish the same. We then
  use a reduction to modify the Tuple.
  """
  @spec update(state :: State.t, key :: any, changes :: [{}]) :: { :ok, true | false }
  def update(%State{ cache: cache }, key, changes) do
    cache
    |> :ets.update_element(key, changes)
    |> handle_update
  end

  @doc """
  Writes a record into the cache, and returns a result signifying whether the
  write was successful or not.
  """
  @spec write(state :: State.t, record :: Record.t) :: { :ok, true | false }
  def write(%State{ cache: cache }, record) do
    { :ok, :ets.insert(cache, record) }
  end

  # Handles the reesult from a read action in order to handle any expirations
  # set against the key. If the key has expired, we purge it immediately to avoid
  # any issues with consistency. If the record is valid, we just return it as is.
  defp handle_read([{ key, touched, ttl, _value } = record], state) do
    if Util.has_expired?(state, touched, ttl) do
      __MODULE__.Del.execute(state, key, @purge_override)
      nil
    else
      record
    end
  end
  defp handle_read(_missing, _state), do: nil

  # Handles an update result, converting a falsey result into a Tuple tagged with
  # the :missing atom. If the result is true, we just return a Tuple tagged with
  # the :ok atom.
  defp handle_update( true), do: { :ok, true }
  defp handle_update(false), do: { :missing, false }

  @doc false
  defmacro __using__(_) do
    quote do
      use Cachex.Constants
      import Cachex.Actions
    end
  end

end
