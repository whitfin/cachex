defmodule Cachex.Actions.Incr do
  @moduledoc false
  # This module controls the action to increment a numeric value for a key inside
  # the cache. It allows for custom amounts to increment by, as well as custom
  # values to place inside the cache before incrementing.

  # we need our imports
  use Cachex.Actions

  # add some aliases
  alias Cachex.Actions.Exists
  alias Cachex.LockManager
  alias Cachex.Record
  alias Cachex.State
  alias Cachex.Util

  @doc """
  Increments a numeric value inside the cache.

  The returned value signals whether the key was in the cache to begin with, or
  has been set to an initial value before being incremented. The value may be
  an error if the key's value is not numeric.

  This action executes inside a write lock to ensure that there are no writes
  currently happening on this key because the increment has to occur after
  the call to exists. We try to execute everything possible before blocking
  the write chain.
  """
  defaction incr(%State{ cache: cache } = state, key, options) do
    amount  = parse_opt(options, :amount,  1)
    initial = parse_opt(options, :initial, 0)

    default = Record.create(state, key, initial)

    LockManager.write(state, key, fn ->
      existed = Exists.execute(state, key, @notify_false)

      try do
        cache
        |> :ets.update_counter(key, { 4, amount }, default)
        |> handle_existed(existed)
      rescue
        _e -> @error_non_numeric_value
      end
    end)
  end

  # Handles the normalization of an incremented value by returning a Tuple to
  # signify whether the value existed before the increment or not. If it did, we
  # return an ok value, if not a false value.
  defp handle_existed(val, { :ok,  true }),
    do: { :ok, val }
  defp handle_existed(val, { :ok, false }),
    do: { :missing, val }

  # Parses an integer option out of the options list. This is just here because
  # it makes the parsing of `amount` and `initial` a little more readable.
  defp parse_opt(opts, key, default) do
    Util.get_opt(opts, key, &is_integer/1, default)
  end

end
