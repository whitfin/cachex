defmodule Cachex.Actions.Stats do

  alias Cachex.Hook
  alias Cachex.State
  alias Cachex.Stats

  def execute(%State{ } = state, options \\ []) when is_list(options) do
    state.post_hooks
    |> Hook.ref_by_module(Cachex.Stats)
    |> handle_hook(state, options)
  end

  defp handle_hook(nil, state, _options) do
    { :error, "Stats not enabled for cache with ref '#{state.cache}'" }
  end
  defp handle_hook(ref, _state, options) do
    { :ok, Stats.retrieve(ref, options) }
  end

end
