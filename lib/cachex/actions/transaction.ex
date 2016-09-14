defmodule Cachex.Actions.Transaction do
  @moduledoc false

  alias Cachex.LockManager
  alias Cachex.State

  def execute(%State{ } = state, keys, operation, options \\ []) when is_list(options) do
    LockManager.transaction(state, keys, fn ->
      state |> operation.() |> handle_result
    end)
  end

  defp handle_result(result) do
    { :ok, result }
  end

end
