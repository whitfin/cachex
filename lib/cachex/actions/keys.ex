defmodule Cachex.Actions.Keys do
  @moduledoc false

  alias Cachex.Actions
  alias Cachex.State
  alias Cachex.Util

  def execute(%State{ } = state, options \\ []) when is_list(options) do
    Actions.do_action(state, { :keys, [ options ] }, fn ->
      { :ok, :ets.select(state.cache, Util.retrieve_all_rows(:key)) }
    end)
  end

end
