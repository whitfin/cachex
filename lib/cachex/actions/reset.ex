defmodule Cachex.Actions.Reset do
  @moduledoc false
  # This module controls a cache reset. Resetting can empty the cache, reset hooks
  # to their initial state, or both. This is not executed inside an Action context
  # because there is no need to notify on reset (as there has been a reset, so it
  # doesn't make sense to always have a reset as the first message).

  # we need our imports
  use Cachex.Actions

  # add some aliases
  alias Cachex.Actions.Clear
  alias Cachex.Hook
  alias Cachex.LockManager
  alias Cachex.State

  @doc """
  Resets various pieces of a cache.

  We can reset either a list of hooks, all hooks, the cache table, or both. We
  do this by reusing the Clear action to empty the cache as needed, and by using
  the reset listener inside a Hook server.

  Nothing in here will notify hooks of the reset as it's quite redundant and it's
  evident that a reset happened when you see that your hook has reinitialized.
  """
  def execute(%State{ } = state, options) do
    LockManager.transaction(state, [ ], fn ->
      only =
        options
        |> Keyword.get(:only, [ :cache, :hooks ])
        |> List.wrap

      state
      |> reset_cache(only)
      |> reset_hooks(only, options)

      { :ok, true }
    end)
  end

  # Handles the resetting of a cache. A cache is only emptied if the cache is set
  # to be reset. Otherwise we just return the state as-is without modifying the
  # cache table.
  defp reset_cache(state, only) do
    if :cache in only do
      Clear.execute(state, @notify_false)
    end
    state
  end

  # Controls the resetting of any hooks, either all or a subset. We have a small
  # optimization here to detect when we want to reset all hooks, to avoid filtering
  # without cause. We use a MapSet just to avoid the O(N) lookups otherwise.
  defp reset_hooks(%State{ pre_hooks: pre, post_hooks: post } = state, only, opts) do
    if :hooks in only do
      state_hooks = Enum.concat(pre, post)

      unless Enum.empty?(state_hooks) do
        case Keyword.get(opts, :hooks) do
          nil ->
            Enum.each(state_hooks, &notify_reset/1)
          val ->
            hset =
              val
              |> List.wrap
              |> MapSet.new

            state_hooks
            |> Enum.filter(&should_reset?(&1, hset))
            |> Enum.each(&notify_reset/1)
        end
      end
    end
    state
  end
  # This function determines if a hook should be reset. It should only be reset
  # if it exists inside the set of hooks to reset.
  defp should_reset?(%Hook{ module: mod }, hook_set) do
    MapSet.member?(hook_set, mod)
  end

  # Notifies a hook of the reset. This simply forwards the hook arguments to the
  # hook alongside a reset message to signal that the hook needs to reinitialize.
  # There is a listener built into the server implementation backing hooks which
  # will handle this automatically, so there's nothing more we need to do.
  defp notify_reset(%Hook{ args: args, ref: ref }) do
    send(ref, { :notify, { :reset, args } })
  end

end
