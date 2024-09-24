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
  alias Cachex.Hook

  # need our macros
  import Cachex.Error
  import Cachex.Spec

  # add our aliases
  alias Cachex.Options

  # update increments
  @update_calls [
    :expire,
    :expire_at,
    :persist,
    :refresh,
    :touch,
    :update
  ]

  @doc """
  Retrieves the latest statistics for a cache.
  """
  @spec for_cache(cache :: Cachex.t()) :: {:ok, map()} | {:error, atom()}
  def for_cache(cache() = cache) do
    case Hook.locate(cache, __MODULE__) do
      nil ->
        error(:stats_disabled)

      hook(name: name) ->
        GenServer.call(name, :retrieve)
    end
  end

  ####################
  # Server Callbacks #
  ####################

  @doc false
  def actions,
    do: :all

  @doc false
  # Initializes this hook with a new stats container.
  #
  # The `:creationDate` field is set inside the `:meta` field to contain the date
  # at which the statistics container was first created (which is more of less
  # equivalent to the start time of the cache).
  def init(_options),
    do: {:ok, %{meta: %{creation_date: now()}}}

  @doc false
  # Retrieves the current stats container.
  #
  # This will just return the internal state to the calling process.
  def handle_call(:retrieve, _ctx, stats),
    do: {:reply, {:ok, stats}, stats}

  @doc false
  # Registers an action against the stats container.
  #
  # This clause will match against any failed requests and short-circuit to
  # avoid artificially adding errors to the statistics. In future it might
  # be that we want to track this, so this might change at some point.
  #
  # coveralls-ignore-start
  def handle_notify(_action, {:error, _result}, stats),
    do: {:ok, stats}

  # coveralls-ignore-stop

  @doc false
  # Registers an action against the stats container.
  #
  # This will increment the call count for every action taken on a cache, as
  # well as incrementing the operation count (although this could be computed
  # from the call counts).
  #
  # It will then pass the statistics on to `register_action/3` in order to
  # allow call specific statistics to be incremented. Note that the order of
  # `register_action/3` is naively ordered to try and optimize for frequency.
  def handle_notify({call, _args} = action, result, stats) do
    stats
    |> increment([:calls, call], 1)
    |> increment([:operations], 1)
    |> register_action(action, result)
    |> wrap(:ok)
  end

  ################
  # Registration #
  ################

  # Handles registration of `get()` command calls.
  #
  # This will increment the hits/misses of the stats container, based on
  # whether the value pulled back is `nil` or not (as `nil` is treated as
  # a missing value through Cachex as of v3).
  defp register_action(stats, {:get, _args}, {_tag, nil}),
    do: increment(stats, [:misses], 1)

  defp register_action(stats, {:get, _args}, {_tag, _value}),
    do: increment(stats, [:hits], 1)

  # Handles registration of `put()` command calls.
  #
  # These calls will just increment the `:writes` count of the statistics
  # container, but only if the write succeeded (as determined by the value).
  defp register_action(stats, {:put, _args}, {_tag, true}),
    do: increment(stats, [:writes], 1)

  # Handles registration of `put_many()` command calls.
  #
  # This is the same as the `put()` handler except that it will count the
  # number of pairs being processed when incrementing the `:writes` key.
  defp register_action(stats, {:put_many, [pairs | _]}, {_tag, true}),
    do: increment(stats, [:writes], length(pairs))

  # Handles registration of `del()` command calls.
  #
  # Cache deletions will increment the `:evictions` key count, based on
  # whether the call succeeded (i.e. the result value is truthy).
  defp register_action(stats, {:del, _args}, {_tag, true}),
    do: increment(stats, [:evictions], 1)

  # Handles registration of `purge()` command calls.
  #
  # A purge call will increment the `:evictions` key using the count of
  # purged keys as the number to increment by. The `:expirations` key
  # will also be incremented in the same way, to surface TTL deletions.
  defp register_action(stats, {:purge, _args}, {_status, count}) do
    stats
    |> increment([:expirations], count)
    |> increment([:evictions], count)
  end

  # Handles registration of `fetch()` command calls.
  #
  # This will delegate through to `register_fetch/2` as the logic is
  # more complicated, and this will keep down the noise of head matches.
  defp register_action(stats, {:fetch, _args}, {label, _value}),
    do: register_fetch(stats, label)

  # Handles registration of `incr()` command calls.
  #
  # This delegates through to `register_increment/4` as the logic is a
  # little more complicated, and this will keep down the noise of matches.
  defp register_action(stats, {:incr, _args} = action, result),
    do: register_increment(stats, action, result, -1)

  # Handles registration of `decr()` command calls.
  #
  # This delegates through to `register_increment/4` as the logic is a
  # little more complicated, and this will keep down the noise of matches.
  defp register_action(stats, {:decr, _args} = action, result),
    do: register_increment(stats, action, result, 1)

  # Handles registration of `update()` command calls.
  #
  # This will increment the `:updates` key if the value signals that the
  # update was successful, otherwise nothing will be modified.
  defp register_action(stats, {:update, _args}, {_tag, true}),
    do: increment(stats, [:updates], 1)

  # Handles registration of `clear()` command calls.
  #
  # This operates in the same way as the `del()` call statistics, except that
  # a count is received in the result, and is used to increment by instead.
  defp register_action(stats, {:clear, _args}, {_tag, count}),
    do: increment(stats, [:evictions], count)

  # Handles registration of `exists?()` command calls.
  #
  # The result boolean will determine whether this increments the `:hits` or
  # `:misses` key of the main statistics container (true/false respectively).
  defp register_action(stats, {:exists?, _args}, {_tag, true}),
    do: increment(stats, [:hits], 1)

  defp register_action(stats, {:exists?, _args}, {_tag, false}),
    do: increment(stats, [:misses], 1)

  # Handles registration of `take()` command calls.
  #
  # Take calls are a little complicated because they need to increment the
  # global eviction count (due to removal) but also increment the global
  # hit/miss count, in addition to the status in the `:take` namespace.
  defp register_action(stats, {:take, _args}, {_tag, nil}),
    do: increment(stats, [:misses], 1)

  defp register_action(stats, {:take, _args}, _result) do
    stats
    |> increment([:hits], 1)
    |> increment([:evictions], 1)
  end

  # Handles registration of `invoke()` command calls.
  #
  # This will increment a custom invocations map to track custom command calls.
  defp register_action(stats, {:invoke, [cmd | _args]}, {:ok, _value}),
    do: increment(stats, [:invocations, cmd], 1)

  # Handles registration of updating command calls.
  #
  # All of the matches calls (dictated by @update_calls) will increment the main
  # `:updates` key in the statistics map only if the value is received as `true`.
  defp register_action(stats, {action, _args}, {_tag, true})
       when action in @update_calls,
       do: increment(stats, [:updates], 1)

  # No-op to avoid crashing on other statistics.
  defp register_action(stats, _action, _result),
    do: stats

  ########################
  # Registration Helpers #
  ########################

  # Handles tracking `fetch()` results based on the result tag.
  #
  # If there's an `:ok`, the value existed and so the `:hits` stat needs to
  # be incremented. If not, we need to increment the `:misses` count. In the
  # case of a miss, we also need to check for `:commit` vs `:ignore` to know
  # whether we should be updating the `:writes` key too.
  defp register_fetch(stats, :ok),
    do: increment(stats, [:hits], 1)

  defp register_fetch(stats, :commit) do
    stats
    |> register_fetch(:ignore)
    |> increment([:writes], 1)
  end

  defp register_fetch(stats, :ignore) do
    stats
    |> increment([:fetches], 1)
    |> increment([:misses], 1)
  end

  # Handles increment calls coming via `incr()` or `decr()`.
  #
  # The logic is the same for both, except for the provided offset (which is
  # basically just a sign flip). It's split out as it's a little more involved
  # than a basic stat count as we need to reverse the arguments to determine if
  # there was a new write or an update (based on the initial/amount arguments).
  defp register_increment(stats, {_type, args}, {_tag, value}, offset) do
    amount = Enum.at(args, 1, 1)
    options = Enum.at(args, 2, [])

    matcher = value + amount * offset

    case Options.get(options, :default, &is_integer/1, 0) do
      ^matcher ->
        increment(stats, [:writes], 1)

      _anything_else ->
        increment(stats, [:updates], 1)
    end
  end

  ##########################
  # Registration Utilities #
  ##########################

  # Increments statistics in the statistics container.
  #
  # This accepts a list of fields to specify the path to the key to increment,
  # much like the `update_in` provided in more recent versions of Elixir.
  defp increment(stats, [head], amount),
    do: Map.update(stats, head, amount, &(&1 + amount))

  defp increment(stats, [head | tail], amount) do
    Map.put(
      stats,
      head,
      case Map.get(stats, head) do
        nil -> increment(%{}, tail, amount)
        map -> increment(map, tail, amount)
      end
    )
  end
end
