defmodule Cachex.Actions.Stream do
  @moduledoc false
  # This module handles the Streaming implementation of a cache. A Stream is a
  # lazy consumer of a cache in that it allows iteration of a cache on-demand.
  # Note that streams do not currenty respect expirations, although this may
  # change in future.

  # we need our imports
  import Cachex.Actions
  import Cachex.Errors
  import Cachex.Spec

  # add some aliases
  alias Cachex.Util

  # our test record for testing matches
  @test { "key", now(), 1000, "value" }

  @doc """
  Creates a Stream for a cache.

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
  creating a cursor or the Stream itself.
  """
  defaction stream(cache(name: name) = cache, options) do
    spec =
      options
      |> Keyword.get(:of, { { :key, :value } })
      |> Util.retrieve_all_rows

    @test
    |> :ets.test_ms(spec)
    |> handle_test(name, spec)
  end

  # Handles the result of testing the users match spec. If it's invalid we just
  # return an error and halt execution. If it's a valid match, we return a new
  # stream inside an ok Tuple after initializing it with the given spec.
  defp handle_test({ :ok, _result }, name, spec),
    do: { :ok, init_stream(name, spec) }
  defp handle_test({ :error, _result }, _name, _spec),
    do: error(:invalid_match)

  # Initializes a Stream resource using an underlying ETS cursor as the resource.
  # Every time more items are requested, we pull another batch of items until the
  # cursor is finished, in which case we halt the Stream and kill the cursor.
  defp init_stream(name, spec) do
    Stream.resource(
      fn ->
        name
        |> :ets.table([ { :traverse, { :select, spec } }])
        |> :qlc.cursor
      end,
      &iterate/1,
      &:qlc.delete_cursor/1
    )
  end

  # Iterates a cursor by pulling back the next batch of items from the cursor
  # and passing them through to `handle_answers/2` to be correctly formed.
  defp iterate(cursor) do
    cursor
    |> :qlc.next_answers
    |> handle_answers(cursor)
  end

  # Handles a result set from a query cursor. If the result set it empty, we just
  # halt the Stream, otherwise we return the next batch of answers alongside the
  # query cursor, in order to close the cursor in the cleanup phase.
  defp handle_answers([ ], cursor),
    do: { :halt, cursor }
  defp handle_answers(ans, cursor),
    do: { ans, cursor }
end
