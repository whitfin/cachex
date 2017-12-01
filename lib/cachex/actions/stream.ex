defmodule Cachex.Actions.Stream do
  @moduledoc """
  Command module to allow streaming of cache entries.

  A cache `Stream` is a lazy consumer of a cache in that it allows iteration
  of a cache on an as-needed basis. It should be noted that streams do not
  currently support record expirations, although this may change in future.
  """
  alias Cachex.Util

  # we need our imports
  import Cachex.Actions
  import Cachex.Errors
  import Cachex.Spec

  # our test record for testing matches
  @test { "key", now(), 1000, "value" }

  @doc """
  Creates a new `Stream` for a given cache.

  Streams are a moving window of a cache, in that they will reflect the latest
  changes in a cache once they're consumed. For example, if you create a Stream
  and consume it 15 minutes later, you'll see all changes which occurred in those
  15 minutes.

  You can provide custom structures to stream using via the `:of` option, but
  as of yet there is no way to query before consumption - meaning that you'll
  have to filter the Stream itself rather than avoiding buffering in the first
  place - this may change in future.

  We execute an `:ets.test_ms/2` call before doing anything to ensure the user
  has provided a valid return type. If they haven't, we return an error before
  creating a cursor or the `Stream` itself.
  """
  defaction stream(cache(name: name) = cache, options) do
    spec =
      options
      |> Keyword.get(:of, { { :key, :value } })
      |> Util.retrieve_all_rows

    case :ets.test_ms(@test, spec) do
      { :ok, _result } ->
        { :ok, init_stream(name, spec) }
      { :error, _result } ->
        error(:invalid_match)
    end
  end

  # Initializes a `Stream` resource from an underlying ETS cursor.
  #
  # Each time more items are requested we pull another batch of entries until
  # the cursor is spent, in which case we halt the stream and kill the cursor.
  defp init_stream(name, spec) do
    Stream.resource(
      fn ->
        name
        |> :ets.table([ { :traverse, { :select, spec } }])
        |> :qlc.cursor
      end,
      fn(cursor) ->
        case :qlc.next_answers(cursor) do
          [ ] -> { :halt, cursor }
          ans -> {   ans, cursor }
        end
      end,
      &:qlc.delete_cursor/1
    )
  end
end
