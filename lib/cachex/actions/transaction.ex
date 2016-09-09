defmodule Cachex.Actions.Transaction do

  @packed [ :ok, :error, :loaded, :missing ]

  alias Cachex.LockManager
  alias Cachex.State
  alias Cachex.Util

  def execute(%State{ } = state, operation, options \\ []) when is_list(options) do
    LockManager.transaction(state, get_keys(options), fn ->
      state |> operation.() |> pack
    end)
  end

  defp get_keys(options) do
    Util.get_opt_list(options, :keys, [])
  end

  defp pack({ status, _ } = value) when status in @packed, do: value
  defp pack(value), do: Util.ok(value)

end
