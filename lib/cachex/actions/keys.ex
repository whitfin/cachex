defmodule Cachex.Actions.Keys do

  alias Cachex.Actions
  alias Cachex.State
  alias Cachex.Util

  def execute(%State{ } = state, options \\ []) when is_list(options) do
    Actions.do_action(state, { :keys, [ options ] }, fn ->
      state.cache
      |> :ets.select(Util.retrieve_all_rows(:key))
      |> Util.ok
    end)
  end

end
