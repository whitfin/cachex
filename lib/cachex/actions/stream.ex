defmodule Cachex.Actions.Stream do
  @moduledoc false

  alias Cachex.Actions
  alias Cachex.Errors
  alias Cachex.State
  alias Cachex.Util

  @test_tpl { "key", Util.now(), nil, "value" }

  def execute(%State{ cache: cache } = state, options \\ []) when is_list(options) do
    Actions.do_action(state, { :stream,  [ options ] }, fn ->
      spec =
        options
        |> Keyword.get(:of, { { :key, :value } })
        |> Util.retrieve_all_rows

      @test_tpl
      |> :ets.test_ms(spec)
      |> handle_test(cache, spec)
    end)
  end

  defp handle_test({ :ok, _result }, cache, spec) do
    { :ok, init_stream(cache, spec) }
  end
  defp handle_test({ :error, _result }, _cache, _spec) do
    Errors.invalid_match()
  end

  defp init_stream(cache, spec) do
    Stream.resource(
      fn ->
        cache
        |> :ets.table([ { :traverse, { :select, spec } }])
        |> :qlc.cursor
      end,
      &iterate/1,
      &:qlc.delete_cursor/1
    )
  end

  defp iterate(cursor) do
    case :qlc.next_answers(cursor) do
      [] -> { :halt, cursor }
      li -> { li, cursor }
    end
  end

end
