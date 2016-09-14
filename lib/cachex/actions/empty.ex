defmodule Cachex.Actions.Empty do
  @moduledoc false

  alias Cachex.Actions
  alias Cachex.Actions.Size
  alias Cachex.State

  def execute(%State{ } = state, options \\ []) when is_list(options) do
    Actions.do_action(state, { :empty?, [ options ] }, fn ->
      case Size.execute(state, notify: false) do
        { :ok, 0 } ->
          { :ok, true }
        _other_value_ ->
          { :ok, false }
      end
    end)
  end

end
