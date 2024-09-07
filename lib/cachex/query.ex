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
  Create a query specification for a cache.

  This is a convenience binding to ETS select specifications, so please see
  the appropriate documentation for any additional information on how to (e.g.)
  format filter clauses and outputs.

  ## Options

    * `:expired`

      Whether to filter expired records or not, with the default being no
      filtering. Setting this to `true` will only retrieve expired records,
      while setting to `false` will only retrieve unexpired records.

    * `:output`

      The query output format, which defaults to `:entry` (retrieving the entire
      cache entry). You can provide any of the entry record fields, with bindings
      such as tuples (`{:key, :value}`) or lists `[:key, :value]` or as a single
      value (`:key`).

    * `:where`

      An ETS filter condition used to locate records in the table. This defaults to
      retrieving all records, and is automatically joined with the value of the
      `:expired` flag for convenience.

  """
  @spec create(options :: Keyword.t()) :: [{tuple, [tuple], [any]}]
  def create(options \\ []),
    do: [
      {
        @header,
        [
          options
          |> Keyword.get(:where, true)
          |> map_clauses
        ],
        [
          options
          |> Keyword.get(:output, :entry)
          |> map_clauses
          |> clean_return
        ]
      }
    ]

  @doc """
  Create a filter against expired records in a cache.

  This function accepts a subfilter to join to create more complex filters.
  """
  @spec expired(filter :: boolean() | tuple()) :: tuple
  def expired(filter \\ nil),
    do: wrap_condition(filter, {:not, unexpired()})

  @doc """
  Create a filter against unexpired records in a cache.

  This function accepts a subfilter to join to create more complex filters.
  """
  @spec unexpired(filter :: boolean() | tuple()) :: tuple
  def unexpired(filter \\ nil),
    do:
      wrap_condition(
        filter,
        {:orelse, {:==, map_clauses(:expiration), nil},
         {:>, {:+, map_clauses(:modified), map_clauses(:expiration)}, now()}}
      )

  ###############
  # Private API #
  ###############

  # Sanitizes a returning value clause.
  #
  # This will just wrap any non-single element Tuples being returned as
  # this is required in order to provide valid return formats.
  defp clean_return(tpl) when tuple_size(tpl) > 1,
    do: {tpl}

  defp clean_return(val),
    do: val

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
  for key <- Keyword.keys(entry(entry())) do
    defp map_clauses(unquote(key)),
      do: :"$#{entry(unquote(key))}"
  end

  # whole cache entry
  defp map_clauses(:entry),
    do: :"$_"

  # no-op, already valid
  defp map_clauses(value),
    do: value

  # Wrap a where clause with a new condition only if the whre clause
  # isn't simply true; if so, defer to the provided condition.
  defp wrap_condition(filter, subfilter) when filter in [nil, true],
    do: subfilter

  defp wrap_condition(filter, subfilter),
    do: {:andalso, subfilter, filter}
end
