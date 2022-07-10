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
  alias Cachex.Services.Janitor

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
  @spec read(Spec.cache(), any) :: Spec.entry() | nil
  def read(cache(name: name) = cache, key) do
    case :ets.lookup(name, key) do
      [] ->
        nil

      [entry] ->
        case Janitor.expired?(cache, entry) do
          false ->
            entry

          true ->
            Cachex.del(cache, key, const(:purge_override))
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
  @spec update(Spec.cache(), any, [tuple]) :: {:ok, boolean}
  def update(cache(name: name), key, changes),
    do: {:ok, :ets.update_element(name, key, changes)}

  @doc """
  Writes a new entry into a cache.
  """
  @spec write(Spec.cache(), [Spec.entry()]) :: {:ok, boolean}
  def write(cache(name: name), entries),
    do: {:ok, :ets.insert(name, entries)}

  @doc """
  Returns the operation used for a write based on a prior value.
  """
  @spec write_op(atom) :: atom
  def write_op(nil),
    do: :put

  def write_op(_tag),
    do: :update

  ##########
  # Macros #
  ##########

  @doc """
  Normalizes a value into a Courier-friendly tagged Tuple.

  If the value is tagged with `:commit`, `:ignore` or `:error`,
  it will be left alone; otherwise it will be wrapped and treated
  as a `:commit` Tuple.
  """
  defmacro normalize_commit(value) do
    quote bind_quoted: [value: value] do
      case value do
        {:error, _value} ->
          value

        {:commit, _value} ->
          value

        {:ignore, _value} ->
          value

        raw_value ->
          {:commit, raw_value}
      end
    end
  end
end
