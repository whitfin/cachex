defmodule Cachex.Actions.Count do
  @moduledoc false

  alias Cachex.Actions
  alias Cachex.State
  alias Cachex.Util

  def execute(%State{ } = state, options \\ []) when is_list(options) do
    Actions.do_action(state, { :count, [ options ] }, fn ->
      { :ok, :ets.select_count(state.cache, Util.retrieve_all_rows(true)) }
    end)
  end

end
