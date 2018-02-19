defmodule Cachex.Query do
  @moduledoc """
  Utility module based around creation of cache queries.

  Queries are essentially just some minor convenience wrappers around the
  internal match specification used by ETS. This module is exposed to make
  it easier to query a cache (via `Cachex.stream/3`) without having to take
  care of filtering for expirations by hand.

  Note that there is almost no validation in here, so test thoroughly and
  store compile-time versions of your queries when possible (as performance
  is not taken into account inside this module; it can be slow to generate).
  """
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Creates an expiration-aware query.
  """
  @spec create_query(any, any) :: [ { tuple, [ tuple ], [ any ] } ]
  def create_query(condition, output \\ :"$_"),
    do: create_raw_query({ :andalso, create_unexpired_clause(), condition }, output)

  @doc """
  Creates a raw query, ignoring expiration.
  """
  @spec create_raw_query(any, any) :: [ { tuple, [ tuple ], [ any ] } ]
  def create_raw_query(condition, output \\ :"$_"),
    do: [ {
      { :_, :"$1", :"$2", :"$3", :"$4" },
      [ map_clauses(condition) ],
      [ clean_return(map_clauses(output)) ]
    } ]

  @doc """
  Creates a match condition for expired records.
  """
  @spec create_expired_clause :: tuple
  def create_expired_clause,
    do: { :not, create_unexpired_clause() }

  @doc """
  Creates a query to retrieve all expired records.
  """
  @spec create_expired_query(any) :: [ { tuple, [ tuple ], [ any ] } ]
  def create_expired_query(output \\ :"$_"),
    do: create_raw_query(create_expired_clause(), output)

  @doc """
  Creates a match condition for unexpired records.
  """
  @spec create_unexpired_clause :: tuple
  def create_unexpired_clause,
    do: { :orelse, { :==, :"$3", nil }, { :>, { :+, :"$2", :"$3" }, now() } }

  @doc """
  Creates a query to retrieve all unexpired records.
  """
  @spec create_unexpired_query(any) :: [ { tuple, [ tuple ], [ any ] } ]
  def create_unexpired_query(output \\ :"$_"),
    do: create_raw_query(create_unexpired_clause(), output)

  ###############
  # Private API #
  ###############

  # Recursively replaces all entry tags in a clause value.
  #
  # This allows the use of entry fields, such as `:key` as references in
  # query clauses (even if ETS doesn't). The fields will be mapped to the
  # index equivalent and returned in a sanitized clause value.
  defp map_clauses(tpl) when is_tuple(tpl) do
    tpl
    |> Tuple.to_list
    |> map_clauses
    |> List.to_tuple
  end
  defp map_clauses(list) when is_list(list),
    do: Enum.map(list, &map_clauses/1)

  # basic entry field name substitution
  for key <- Keyword.keys(entry(entry())),
    do: defp map_clauses(unquote(key)),
      do: :"$#{entry(unquote(key))}"

  # no-op, already valid
  defp map_clauses(field),
    do: field

  # Sanitizes a returning value clause.
  #
  # This will just wrap any non-single element Tuples being returned as
  # this is required in order to provide valid return formats.
  defp clean_return(tpl) when tuple_size(tpl) > 1,
    do: { tpl }
  defp clean_return(val),
    do: val
end
