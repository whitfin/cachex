defmodule Cachex.Actions.Reset do
  @moduledoc false

  alias Cachex.Actions.Clear
  alias Cachex.Hook
  alias Cachex.State

  def execute(%State{ } = state, options \\ []) when is_list(options) do
    only =
      options
      |> Keyword.get(:only, [ :cache, :hooks ])
      |> List.wrap

    state
    |> reset_cache(only, options)
    |> reset_hooks(only, options)

    { :ok, true }
  end

  defp reset_cache(state, only, _opts) do
    if Enum.member?(only, :cache) do
      Clear.execute(state, notify: false)
    end
    state
  end

  defp reset_hooks(state, only, opts) do
    if Enum.member?(only, :hooks) do
      state_hooks = Hook.combine(state)

      hooks_list = case Keyword.get(opts, :hooks) do
        nil -> Enum.map(state_hooks, &(&1.module))
        val -> List.wrap(val)
      end

      state_hooks
      |> Enum.filter(&(&1.module in hooks_list))
      |> Enum.each(&send(&1.ref, { :notify, { :reset, &1.args } }))
    end
    state
  end

end
