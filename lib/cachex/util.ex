defmodule Cachex.Util do
  @moduledoc false
  # Small utility module for common functions use through Cachex.
  #
  # This is 100% internal API, never use it from outside.
  import Cachex.Spec

  # pre-calculated memory size
  @memory_exponent :math.log(1024)

  # internal map of memory suffixes
  @memory_suffixes %{
    0.0 => "B",
    1.0 => "KiB",
    2.0 => "MiB",
    3.0 => "GiB",
    4.0 => "TiB"
  }

  # the number of suffixes stored (not including B)
  @memory_sufcount map_size(@memory_suffixes) - 1.0

  # available result tuple tag list
  @result_tags [ :commit, :ignore, :error ]

  ##############
  # Public API #
  ##############

  # result tuple tag type
  @type result_tag :: :commit | :ignore | :error

  @doc """
  Converts a number of bytes to a binary representation.

  Just to avoid confusion, binary here means human readable. We only support up
  to TiB. Anything over will just group under TiB. For example, a PiB would be
  `16384.00 TiB`.
  """
  @spec bytes_to_readable(integer) :: binary
  def bytes_to_readable(bytes) when is_integer(bytes) do
    index =
      bytes
      |> :math.log
      |> :erlang./(@memory_exponent)
      |> Float.floor
      |> :erlang.min(@memory_sufcount)

    abbrev = bytes / :math.pow(1024, index)
    suffix = Map.get(@memory_suffixes, index)

    "~.2f ~s"
    |> :io_lib.format([ abbrev, suffix ])
    |> IO.iodata_to_binary
  end

  @doc """
  Creates a match specification using the provided rules.

  This is a shorthand to write a cache-compatible ETS match.
  """
  @spec create_match(any, any) :: [ { { }, [ any ], [ any ] }]
  def create_match(return, where) do
    nwhere = case where do
      [ where ] -> where
        where   -> where
    end

    [
      {
        { :_, :"$1", :"$2", :"$3", :"$4" },
        List.wrap(do_field_normalize(nwhere)),
        List.wrap(do_field_normalize(return))
      }
    ]
  end

  @doc """
  Normalizes a commit result to a Tuple tagged with `:commit`, `:ignore`
  or `:error`.
  """
  @spec normalize_commit({ result_tag, any } | any) :: { result_tag, any }
  def normalize_commit(value) do
    case value do
      { status, _val } when status in @result_tags ->
        value
      ^value ->
        { :commit, value }
    end
  end

  @doc """
  Returns a match for all entries in a table.

  This allows you to customize what is returned using the return param.
  """
  @spec retrieve_all_rows([ any ]) :: [ { { }, [ any ], [ any ] }]
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
  Returns a match for all expired entries in a table.

  This allows you to customize what is returned using the return param.
  """
  @spec retrieve_expired_rows([ any ]) :: [ { { }, [ any ], [ any ] }]
  def retrieve_expired_rows(return) do
    create_match(return, [
      {
        :andalso,                                 # guards for matching
        { :"/=", :"$3", nil },                    # where a TTL is set
        { :"<", { :"+", :"$2", :"$3" }, now() }   # and the TTL has passed
      }
    ])
  end

  ###############
  # Private API #
  ###############

  # Normalizes select syntax to valid Erlang handles.
  #
  # This is used to reference field names from an entry using the name from
  # the entry record. This is a recursive normalization to function all the
  # way down (as matches are arbitrarily nested).
  #
  # TODO: we need to kill this with fire at some point
  defp do_field_normalize(fields) when is_tuple(fields) do
    fields
    |> Tuple.to_list
    |> Enum.map(&do_field_normalize/1)
    |> List.to_tuple
  end
  defp do_field_normalize(:key),
    do: :"$#{entry(:key)}"
  defp do_field_normalize(:value),
    do: :"$#{entry(:value)}"
  defp do_field_normalize(:touched),
    do: :"$#{entry(:touched)}"
  defp do_field_normalize(:ttl),
    do: :"$#{entry(:ttl)}"
  defp do_field_normalize(field),
    do: field
end
