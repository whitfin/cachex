defmodule Cachex.Actions do
  @moduledoc """
  Parent actions module for cache interactions.

  This module contains foundation actions required to implement cache actions,
  such as typical CRUD style operations on cache entries. It also provides the
  `defaction/2` macro which enables command definition which injects notifications
  for cache hooks.
  """
  import Cachex.Spec

  # add some aliases
  alias Cachex.Services.Informant
  alias Cachex.Util

  ##############
  # Public API #
  ##############

  @doc """
  Retrieves an entry from a cache.

  If the entry does not exist, a `nil` value will be returned. Likewise
  if the  entry has expired, we lazily remove it (if enabled) and return
  a `nil` value.

  This will return an instance of an entry record as defined in the main
  `Cachex.Spec` module, rather than just the raw value.
  """
  @spec read(Spec.cache, any) :: Spec.entry | nil
  def read(cache(name: name) = cache, key) do
    case :ets.lookup(name, key) do
      [] ->
        nil
      [ entry ] ->
        case Util.has_expired?(cache, entry) do
          false ->
            entry
          true  ->
            __MODULE__.Del.execute(cache, key, const(:purge_override))
            nil
        end
    end
  end

  @doc """
  Updates a collection of fields inside a cache entry.

  This is done in a single call due to the use of `:ets.update_element/3` which
  allows multiple changes in a group. This will return a boolean to represent
  whether the update was successful or not.

  Note that updates are atomic; either all updates will take place, or none will.
  """
  @spec update(Spec.cache, any, [ tuple ]) :: { :ok, boolean }
  def update(cache(name: name), key, changes) do
    case :ets.update_element(name, key, changes) do
      true  -> { :ok, true }
      false -> { :missing, false }
    end
  end

  @doc """
  Writes a new entry into a cache.
  """
  @spec write(Spec.cache, [ Spec.entry ]) :: { :ok, boolean }
  def write(cache(name: name), entries),
    do: { :ok, :ets.insert(name, entries) }

  ##########
  # Macros #
  ##########

  @doc """
  This macro provides a base Action template.

  An action is a series of ETS operations which notify any cache Hooks both before
  and after they execute. Rather than have this hand-written or use anonymous
  functions, we provide a macro here. Simply use `defaction` instead of `def`
  in the action declarations and notifications will be handled automatically.

  It should be noted that the function name will be `execute` with the defined
  arity. This is because it makes little sense to do `Cachex.Actions.Ttl.ttl()`,
  for example.
  """
  defmacro defaction({ name, _line, [ _cache | stateless_args ] = arguments }, do: body) do
    quote do
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
end
