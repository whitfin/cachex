defmodule Cachex.Actions.Purge do
  @moduledoc false

  alias Cachex.Actions
  alias Cachex.Janitor
  alias Cachex.State

  def execute(%State{ } = state, options \\ []) when is_list(options) do
    Actions.do_action(state, { :purge, [ options ] }, fn ->
      Janitor.purge_records(state.cache)
    end)
  end

end
