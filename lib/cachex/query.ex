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

  # raw query header
  @header entry()
          |> entry()
          |> Enum.with_index(1)
          |> Enum.map(fn {_, idx} -> :"$#{idx}" end)
          |> Enum.reverse()
          |> Enum.concat([:_])
          |> Enum.reverse()
          |> List.to_tuple()

  ##############
  # Public API #
  ##############

  @doc """
  Creates a query to retrieve all expired records.
  """
  @spec expired(any) :: [{tuple, [tuple], [any]}]
  def expired(output \\ :entry),
    do: raw(expired_clause(), output)

  @doc """
  Creates a match condition for expired records.
  """
  @spec expired_clause :: tuple
  def expired_clause,
    do: {:not, unexpired_clause()}

  @doc """
  Creates a raw query, ignoring expiration.
  """
  @spec raw(any, any) :: [{tuple, [tuple], [any]}]
  def raw(condition, output \\ :entry),
    do: [
      {
        @header,
        [map_clauses(condition)],
        [clean_return(map_clauses(output))]
      }
    ]

  @doc """
  Creates a query to retrieve all unexpired records.
  """
  @spec unexpired(any) :: [{tuple, [tuple], [any]}]
  def unexpired(output \\ :entry),
    do: raw(unexpired_clause(), output)

  @doc """
  Creates a match condition for unexpired records.
  """
  @spec unexpired_clause :: tuple
  def unexpired_clause,
    do:
      {:orelse, {:==, map_clauses(:ttl), nil},
       {:>, {:+, map_clauses(:touched), map_clauses(:ttl)}, now()}}

  @doc """
  Creates an expiration-aware query.
  """
  @spec where(any, any) :: [{tuple, [tuple], [any]}]
  def where(condition, output \\ :entry),
    do: raw({:andalso, unexpired_clause(), condition}, output)

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
    |> Tuple.to_list()
    |> map_clauses
    |> List.to_tuple()
  end

  defp map_clauses(list) when is_list(list),
    do: Enum.map(list, &map_clauses/1)

  # basic entry field name substitution
  for key <- Keyword.keys(entry(entry())),
      do:
        defp(map_clauses(unquote(key)),
          do: :"$#{entry(unquote(key))}"
        )

  # whole cache entry
  defp map_clauses(:entry),
    do: :"$_"

  # no-op, already valid
  defp map_clauses(field),
    do: field

  # Sanitizes a returning value clause.
  #
  # This will just wrap any non-single element Tuples being returned as
  # this is required in order to provide valid return formats.
  defp clean_return(tpl) when tuple_size(tpl) > 1,
    do: {tpl}

  defp clean_return(val),
    do: val
end
