defmodule Cachex.Actions.Stream do
  @moduledoc false

  alias Cachex.Actions
  alias Cachex.State
  alias Cachex.Util

  def execute(%State{ } = state, options \\ []) when is_list(options) do
    Actions.do_action(state, { :stream,  [ options ] }, fn ->
      resource = Stream.resource(
        fn ->
          match_spec =
            options
            |> Keyword.get(:of, { :key, :value })
            |> Util.retrieve_all_rows

          state.cache
          |> :ets.table([ { :traverse, { :select, match_spec } }])
          |> :qlc.cursor
        end,
        fn(cursor) ->
          case :qlc.next_answers(cursor) do
            [] -> { :halt, cursor }
            li -> { li, cursor }
          end
        end,
        &:qlc.delete_cursor/1
      )
      { :ok, resource }
    end)
  end

end
