defmodule Cachex.Actions.Size do

  alias Cachex.Actions
  alias Cachex.State

  def execute(%State{ } = state, options \\ []) when is_list(options) do
    Actions.do_action(state, { :size, [ options ] }, fn ->
      { :ok, :ets.info(state.cache, :size) }
    end)
  end

end
