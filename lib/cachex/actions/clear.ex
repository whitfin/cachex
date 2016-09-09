defmodule Cachex.Actions.Clear do
  @moduledoc false

  alias Cachex.Actions
  alias Cachex.Actions.Size
  alias Cachex.LockManager
  alias Cachex.State

  def execute(%State{ } = state, options \\ []) when is_list(options) do
    Actions.do_action(state, { :clear, [ options ] }, fn ->
      LockManager.transaction(state, [], fn ->
        evicted =
          state
          |> Size.execute(notify: false)
          |> handle_evicted

        :ets.delete_all_objects(state.cache) && evicted
      end)
    end)
  end

  defp handle_evicted({ :ok, _size } = res), do: res
  defp handle_evicted(_other_result), do: { :ok, 0 }

end
