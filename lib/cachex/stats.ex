defmodule Cachex.Stats do
  @moduledoc """
  Hook module to control the gathering of cache statistics.

  This implementation of statistics tracking uses a hook to run asynchronously
  against a cache (so that it doesn't impact those who don't want it). It executes
  as a post hook and provides a solid example of what a hook can/should look like.

  This hook has zero knowledge of the cache it belongs to; it keeps track of an
  internal set of statistics based on the provided messages. This means that it
  can also be mocked easily using raw server calls to `handle_notify/3`.
  """
  use Cachex.Hook

  # need our macros
  import Cachex.Spec
  import Cachex.Errors

  ##############
  # Public API #
  ##############

  @doc """
  Determines if stats are enabled for a cache.
  """
  @spec enabled?(Spec.cache) :: boolean
  def enabled?(cache() = cache),
    do: locate(cache) != nil

  @doc """
  Locates a stats hook for a cache, if enabled.
  """
  @spec locate(Spec.cache) :: Spec.hook | nil
  def locate(cache(hooks: hooks(post: post_hooks))),
    do: Enum.find(post_hooks, &match?(hook(module: Cachex.Stats), &1))

  @doc """
  Retrieves the latest statistics for a cache.
  """
  @spec retrieve(Spec.cache) :: %{ }
  def retrieve(cache(name: name) = cache) do
    case enabled?(cache) do
      false -> error(:stats_disabled)
      true  ->
        name
        |> name(:stats)
        |> GenServer.call(:retrieve)
    end
  end

  ####################
  # Server Callbacks #
  ####################

  @doc false
  # Initializes this hook with a new stats container.
  #
  # The `:creationDate` field is set inside the `:meta` field to contain the date
  # at which the statistics container was first created (which is more of less
  # equivalent to the start time of the cache).
  def init(_options),
    do: { :ok, %{ meta: %{ creationDate: now() } } }

  @doc false
  # Retrieves the current stats container.
  #
  # This will just return the internal state to the calling process.
  def handle_call(:retrieve, _ctx, stats),
    do: { :reply, { :ok, stats }, stats }

  @doc false
  # Registers an action against the stats container.
  #
  # This clause will match against any failed requests and short-circuit to
  # avoid artificially adding errors to the statistics. In future it might
  # be that we want to track this, so this might change at some point.
  def handle_notify(_action, { :error, _result }, stats),
    do: { :ok, stats }

  @doc false
  # Registers an action against the stats container.
  #
  # This clause will pull out the action from the cache call, as well as the
  # result, and use both to increment various keys in the statistics container
  # to signal exactly what the call represents.
  #
  # This is done by passing off to `register_action/2` internally as we use
  # multiple function head definitions to easily separate action logic.
  def handle_notify({ action, _options }, result, stats) do
    stats
    |> register_action(action, result)
    |> increment(:global, :opCount, 1)
    |> wrap(:ok)
  end

  ###############
  # Private API #
  ###############

  # Handles registration of `clear()` command calls.
  #
  # A clear call returns the number of entries removed, so this will update both
  # the total number of cleared entries as well as the global eviction count.
  defp register_action(stats, :clear, { _status, value }) do
    stats
    |> increment(:clear, :total, value)
    |> increment(:global, :evictionCount, value)
  end

  # Handles registration of `del()` command calls.
  #
  # Deleting a cache entry should increment the delete count
  # and also the global eviction count by 1.
  defp register_action(stats, :del, { _status, value }) do
    tmp = increment(stats, :del, value, 1)
    case value do
      true  -> increment(tmp, :global, :evictionCount, 1)
      false -> tmp
    end
  end

  # Handles registration of `exists?()` command calls.
  #
  # This needs to increment the global hit/miss count based on the value
  # boolean coming back. It will also increment the value key under the
  # `:exists?` action namespace in the statistics container.
  defp register_action(stats, :exists?, { _status, value }) do
    stats
    |> increment(:exists?, value, 1)
    |> increment(:global, value && :hitCount || :missCount, 1)
  end

  # Handles registration of `purge()` command calls.
  #
  # A purge call returns the number of entries removed, so this will update both
  # the total number of purged entries as well as the global expired count.
  defp register_action(stats, :purge, { _status, value }) do
    stats
    |> increment(:purge, :total, value)
    |> increment(:global, :expiredCount, value)
  end

  # Handles registration of `set()` command calls.
  #
  # Set calls will increment the result of the call in the `:set`
  # namespace inside the statistics container. It will also
  # increment the global entry set count.
  defp register_action(stats, :set, { _status, value }) do
    tmp = increment(stats, :set, value, 1)
    case value do
      true  -> increment(tmp, :global, :setCount, 1)
      false -> tmp
    end
  end

  # Handles registration of `take()` command calls.
  #
  # Take calls are a little complicated because they need to increment the
  # global eviction count (due to removal) but also increment the global
  # hit/miss count, in addition to the status in the `:take` namespace.
  defp register_action(stats, :take, { status, _value }) do
    tmp =
      stats
      |> increment(:take, status, 1)
      |> increment(:global, normalize_status(status), 1)

    case status do
      :ok -> increment(tmp, :global, :evictionCount, 1)
      _na -> tmp
    end
  end

  # Handles registration of `ttl()` command calls.
  #
  # This will increment the status in the `:ttl` namespace as well
  # as incrementing the global hit/miss count for the cache.
  defp register_action(stats, :ttl, { status, _value }) do
    stats
    |> increment(:ttl, status, 1)
    |> increment(:global, status == :ok && :hitCount || :missCount, 1)
  end

  # Handles registration of `update()` command calls.
  #
  # This will increment the global update count as well as the value
  # inside the `:update` namespace, to represent an update hit.
  defp register_action(stats, :update, { _status, value }) do
    tmp = increment(stats, :update, value, 1)
    case value do
      true  -> increment(tmp, :global, :updateCount, 1)
      false -> tmp
    end
  end

  # Handles registration of `get()` and `fetch()` command calls.
  #
  # This needs to increment the status in the global container, in addition to adding
  # the status to the namespace of the provided action (either `:get` or `:fetch`).
  defp register_action(stats, action, { status, _value })
  when action in [ :get, :fetch ] do
    stats
    |> increment(action, status, 1)
    |> increment(:global, normalize_status(status), 1)
  end

  # Handles registration of `decr()` and `incr()` command calls.
  #
  # Both of these calls operate in the same way, just negative/positive. We use the
  # status to determine if a new value was inserted or if it was updated. Aside from
  # this we just increment the status in the action namespace, as always.
  defp register_action(stats, action, { status, _value })
  when action in [ :decr, :incr ] do
    stats
    |> increment(action, status, 1)
    |> increment(:global, status == :ok && :updateCount || :setCount, 1)
  end

  # Handles registration of `expire()`, `expire_at()`, `persist()` and `refresh()` calls.
  #
  # This is a common set of updates which changes the global update count alongside the
  # received value in the action namespace, as all of these actions are related and shared.
  defp register_action(stats, action, { _status, value })
  when action in [ :expire, :expire_at, :persist, :refresh ] do
    tmp = increment(stats, action, value, 1)
    case value do
      true  -> increment(tmp, :global, :updateCount, 1)
      false -> tmp
    end
  end

  # Handles the registration of any other calls.
  #
  # This purely increments the action call by 1.
  defp register_action(stats, action, _result),
    do: increment(stats, action, :calls, 1)

  # Increments a given set of statistics in the stats container.
  #
  # We accept a list of fields to work with to increment multiple statistics for
  # an action at the same time, even though this isn't needed at the time of
  # writing.
  #
  # This is a gross function due to the nesting but it's actually quite optimized
  # as of Cachex v3. Further changes will happen later in order to make the stats
  # collection a little more uniform to avoid the complexity involved.
  defp increment(stats, action, fields, amount) do
    { _, updated_stats } = Map.get_and_update(stats, action, fn(inner) ->
      fields_list = List.wrap(fields)

      action_stats =
        Enum.reduce(fields_list, inner || %{}, fn(key, acc) ->
          Map.update(acc, key, amount, &(amount + &1))
        end)

      { nil, action_stats }
    end)
    updated_stats
  end

  # Normalizes a status atom into global fields.
  #
  # This is used to get a list of global fields to increment
  # based on the status returned by an action as it's always
  # the same behaviour regardless of the action executed.
  defp normalize_status(:ok),
    do: [ :hitCount ]
  defp normalize_status(:missing),
    do: [ :missCount ]
  defp normalize_status(:commit),
    do: [ :missCount, :loadCount, :setCount ]
  defp normalize_status(:ignore),
    do: [ :missCount, :loadCount ]
end
