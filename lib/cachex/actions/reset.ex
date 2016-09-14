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

  defp reset_hooks(%State{ pre_hooks: pre, post_hooks: post } = state, only, opts) do
    if Enum.member?(only, :hooks) do
      state_hooks = Enum.concat(pre, post)

      hooks_list = case Keyword.get(opts, :hooks) do
        nil -> Enum.map(state_hooks, &(&1.module))
        val -> List.wrap(val)
      end

      state_hooks
      |> Enum.filter(&should_reset?(&1, hooks_list))
      |> Enum.each(&notify_reset/1)
    end
    state
  end

  defp should_reset?(%Hook{ module: mod }, hooks_list) do
    mod in hooks_list
  end

  defp notify_reset(%Hook{ args: args, ref: ref }) do
    send(ref, { :notify, { :reset, args } })
  end

end
