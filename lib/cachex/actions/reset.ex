defmodule Cachex.Actions.Reset do
  @moduledoc false
  # Command module to enable complete reset of a cache.
  #
  # This command allows the caller to reset a cache to an empty state, reset
  # the hooks associated with a cache, or both.
  #
  # This is not executed inside an action context as there is no need to
  # notify on reset (as otherwise a reset would always be the first message).
  alias Cachex.Hook
  alias Cachex.Actions.Clear
  alias Cachex.Services.Locksmith

  # add the specification
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Resets the internal cache state.

  This will either reset a list of cache hooks, all attached cache hooks, the
  backing cache table, or all of the aforementioned. This is done by reusing
  the `clear()` command to empty the table as needed, and by using the reset
  listener exposed by the hook servers.

  Nothing in here will notify any hooks of resets occurring as it's basically
  quite redundant and it's evident that a reset has happened when you see that
  your hook has reinitialized.
  """
  def execute(cache() = cache, options) do
    Locksmith.transaction(cache, [], fn ->
      only =
        options
        |> Keyword.get(:only, [:cache, :hooks])
        |> List.wrap()

      reset_cache(cache, only, options)
      reset_hooks(cache, only, options)

      {:ok, true}
    end)
  end

  ###############
  # Private API #
  ###############

  # Handles reset of the backing cache table.
  #
  # A cache is only emptied if the `:cache` property appears in the list of
  # cache components to reset. If not provided, this will short circuit and
  # leave the cache table exactly as-is.
  defp reset_cache(cache, only, _options) do
    with true <- :cache in only do
      Clear.execute(cache, [])
    end
  end

  # Handles reset of cache hooks.
  #
  # This has the ability to clear either all hooks or a subset of hooks. We have a small
  # optimization here to detect when we want to reset all hooks to avoid filtering without
  # a real need to. We also convert the list of hooks to a set to avoid O(N) lookups.
  defp reset_hooks(cache(hooks: hooks), only, opts) do
    if :hooks in only do
      hooks = Hook.concat(hooks)

      hooks =
        case Keyword.get(opts, :hooks) do
          nil ->
            hooks

          val ->
            Enum.filter(hooks, &should_reset?(&1, val))
        end

      Enum.each(hooks, &notify_reset/1)
    end
  end

  # Determines if a hook should be reset.
  #
  # This is just sugar around set membership whilst unpacking a hook record,
  # used in Enum iterations to avoid inlining functions for readability.
  defp should_reset?(hook(module: module), hooks),
    do: module in hooks

  # Notifies a hook of a reset.
  #
  # This simply sends the hook state back to the hook alongside a reset
  # message to signal that the hook needs to reinitialize. Hooks have a
  # listener built into the server implementatnion in order to handle this
  # automatically, so there's nothing more we need to do.
  defp notify_reset(hook(args: args, name: name)),
    do: send(name, {:cachex_reset, args})
end
