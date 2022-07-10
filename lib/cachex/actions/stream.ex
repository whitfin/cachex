defmodule Cachex.Actions.Stream do
  @moduledoc false
  # Command module to allow streaming of cache entries.
  #
  # A cache `Stream` is a lazy consumer of a cache in that it allows iteration
  # of a cache on an as-needed basis. It acts as any other `Stream` from Elixir,
  # and is fully compatible with the functions found in the `Enum` module.
  alias Cachex.Options

  # need our imports
  import Cachex.Errors
  import Cachex.Spec

  # our test record for testing matches
  @test entry(
          key: "key",
          touched: now(),
          ttl: 1000,
          value: "value"
        )

  ##############
  # Public API #
  ##############

  @doc """
  Creates a new `Stream` for a given cache.

  Streams are a moving window of a cache, in that they will reflect the latest
  changes in a cache once they're consumed. For example, if you create a Stream
  and consume it 15 minutes later, you'll see all changes which occurred in those
  15 minutes.

  We execute an `:ets.test_ms/2` call before doing anything to ensure the user
  has provided a valid return type. If they haven't, we return an error before
  creating a cursor or the `Stream` itself.
  """
  def execute(cache(name: name), spec, options) do
    case :ets.test_ms(@test, spec) do
      {:ok, _result} ->
        options
        |> Options.get(:batch_size, &is_positive_integer/1, 25)
        |> init_stream(name, spec)
        |> wrap(:ok)

      {:error, _result} ->
        error(:invalid_match)
    end
  end

  ###############
  # Private API #
  ###############

  # Initializes a `Stream` resource from an underlying ETS cursor.
  #
  # Each time more items are requested we pull another batch of entries until
  # the cursor is spent, in which case we halt the stream and kill the cursor.
  defp init_stream(batch, name, spec) do
    Stream.resource(
      fn ->
        name
        |> :ets.table([{:traverse, {:select, spec}}])
        |> :qlc.cursor()
      end,
      fn cursor ->
        case :qlc.next_answers(cursor, batch) do
          [] -> {:halt, cursor}
          ans -> {ans, cursor}
        end
      end,
      &:qlc.delete_cursor/1
    )
  end
end
