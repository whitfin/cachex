defmodule Cachex.Actions.Incr do
  @moduledoc false
  # This module controls the action to increment a numeric value for a key inside
  # the cache. It allows for custom amounts to increment by, as well as custom
  # values to place inside the cache before incrementing.

  # we need our imports
  use Cachex.Include,
    constants: true,
    actions: true,
    models: true

  # add some aliases
  alias Cachex.Actions.Exists
  alias Cachex.Cache
  alias Cachex.Services.Locksmith
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
  defaction incr(%Cache{ name: name } = cache, key, options) do
    amount  = Util.get_opt(options,  :amount, &is_integer/1, 1)
    initial = Util.get_opt(options, :initial, &is_integer/1, 0)
    expiry  = Util.get_expiration(cache, nil)

    default = entry_now(key: key, ttl: expiry, value: initial)

    Locksmith.write(cache, key, fn ->
      existed = Exists.execute(cache, key, @notify_false)

      try do
        name
        |> :ets.update_counter(key, entry_mod(:value, amount), default)
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
end
