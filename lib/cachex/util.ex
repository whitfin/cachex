defmodule Cachex.Util do
  @moduledoc false
  # A small collection of utilities for use throughout the library. Mainly things
  # to do with response formatting and generally just common functions.

  # memory size suffixes
  @sibs ["B", "KiB", "MiB", "GiB", "TiB"]

  # tags which allow Set actions
  @stgs [ :missing, :new ]

  @doc """
  Converts a number of memory bytes to a binary representation.

  Several things to note here:

    1. We only support up to TiB. Anything over will just group under TiB. For
      example, a PiB would be `16384.00 TiB`.
    2. The `/ 1` in the format call is to avoid an argument error, in case it
      hasn't been floated already - e.g. if `size < 1024`.
    3. The list weirdness with `next` is in order to support #1 above. Probably
      more efficient ways, but that seems easiest for now.

  """
  def bytes_to_readable(size, sibs \\ @sibs)
  def bytes_to_readable(size, [ _, next |tail ]) when size >= 1024,
    do: bytes_to_readable(size / 1024, [ next | tail ])
  def bytes_to_readable(size, [ head|_ ]) do
    "~.2f ~s"
    |> :io_lib.format([size / 1, head])
    |> IO.iodata_to_binary
  end

  @doc """
  Creates a match spec for the cache using the provided rules, and returning the
  provided return values. This is just shorthand for writing the same boilerplate
  spec over and over again.
  """
  def create_match(return, where) do
    nwhere = case where do
      [ where ] -> where
        where   -> where
    end

    [
      {
        { :"$1", :"$2", :"$3", :"$4" },
        List.wrap(do_field_normalize(nwhere)),
        List.wrap(do_field_normalize(return))
      }
    ]
  end

  @doc """
  Pulls a value from a set of options. If the value satisfies the condition passed
  in, we return it. Otherwise we return a default value.
  """
  def get_opt(options, key, condition, default \\ nil) do
    opt_transform(options, key, fn(val) ->
      try do
        if condition.(val), do: val, else: default
      rescue
        _ -> default
      end
    end)
  end

  @doc """
  Small utility to figure out if a document has expired based on the last touched
  time and the TTL of the document.
  """
  def has_expired?(%Cachex.State{ ode: false }, _touched, _ttl),
    do: false
  def has_expired?(_state, touched, ttl),
    do: has_expired?(touched, ttl)
  def has_expired?(touched, ttl) when is_number(ttl),
    do: touched + ttl < now()
  def has_expired?(_touched, _ttl),
    do: false

  @doc """
  Shorthand increments for a map key. If the value is not a number, it is assumed
  to be 0.
  """
  def increment_map_key(map, key, amount) do
    Map.update(map, key, amount, fn
      (val) when is_number(val) ->
        amount + val
      (_va) ->
        amount
    end)
  end

  @doc """
  Retrieves the last item in a Tuple. This is just shorthand around sizeof and
  pulling the last element.
  """
  def last_of_tuple(tuple) when is_tuple(tuple) do
    case tuple_size(tuple) do
      0 -> nil
      n -> elem(tuple, n - 1)
    end
  end

  @doc """
  Normalizes a commit result to determine whether we're going to signal to
  commit the changes to the cache, or simply ignore the changes and return.
  """
  def normalize_commit({ :commit, _val } = val),
    do: val
  def normalize_commit({ :ignore, _val } = val),
    do: val
  def normalize_commit(val),
    do: { :commit, val }

  @doc """
  Consistency wrapper around current time in millis.
  """
  def now,
    do: :os.system_time(1000)

  @doc """
  Transforms an option value from inside a Keyword list using a provided transformer.
  """
  def opt_transform(options, key, transformer) do
    options
    |> Keyword.get(key)
    |> transformer.()
  end

  @doc """
  Returns a selection to return the designated value for all rows. Enables things
  like finding all stored keys and all stored values.
  """
  def retrieve_all_rows(return) do
    create_match(return, [
      {
        :orelse,                                  # guards for matching
        { :"==", :"$3", nil },                    # where a TTL is not set
        { :">", { :"+", :"$2", :"$3" }, now() }   # or the TTL has not passed
      }
    ])
  end

  @doc """
  Returns a selection to return the designated value for all expired rows.
  """
  def retrieve_expired_rows(return) do
    create_match(return, [
      {
        :andalso,                                 # guards for matching
        { :"/=", :"$3", nil },                    # where a TTL is set
        { :"<", { :"+", :"$2", :"$3" }, now() }   # and the TTL has passed
      }
    ])
  end

  @doc """
  Wraps a value inside a Tuple with a given tag as first element. This is just a
  convenience function for pipelines.
  """
  def wrap(val, tag), do: { tag, val }

  @doc """
  Finds the module to use for a write action based on the provided tag.

  If the tag is either `:missing` or `:new`, we return the Set action, otherwise
  we return the Update action.
  """
  def write_mod(tag) when tag in @stgs,
    do: Cachex.Actions.Set
  def write_mod(_tag),
    do: Cachex.Actions.Update

  # Used to normalize some quick select syntax to valid Erlang handles. Used when
  # creating match specifications instead of having `$` atoms everywhere.
  defp do_field_normalize(fields) when is_tuple(fields) do
    fields
    |> Tuple.to_list
    |> Enum.map(&do_field_normalize/1)
    |> List.to_tuple
  end
  defp do_field_normalize(:key),
    do: :"$1"
  defp do_field_normalize(:value),
    do: :"$4"
  defp do_field_normalize(:touched),
    do: :"$2"
  defp do_field_normalize(:ttl),
    do: :"$3"
  defp do_field_normalize(field),
    do: field
end
