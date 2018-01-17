defmodule Cachex.Actions.Incr do
  @moduledoc """
  Command module to enable incrementing cache entries.

  This operates on an ETS level for the actual update calls, rather than using
  a transactional context. The result is a faster throughput with the same
  behaviour aspects (but we still lock the key temporarily).
  """
  alias Cachex.Actions.Exists
  alias Cachex.Services.Locksmith
  alias Cachex.Util

  # we need some imports
  import Cachex.Actions
  import Cachex.Errors
  import Cachex.Spec

  ##############
  # Public API #
  ##############

  @doc """
  Increments a numeric value inside the cache.

  Increment calls execute inside a write lock to ensure that there are no
  writes happening due to the existence check before the actual increment
  call. This is annoyingly expensive, but is required to communicate whether
  the key existed already.

  This command will return an error if called on a non-numeric value.
  """
  defaction incr(cache(name: name) = cache, key, amount, options) do
    initial = Util.get_opt(options, :initial, &is_integer/1, 0)
    expiry  = Util.get_expiration(cache, nil)

    default = entry_now(key: key, ttl: expiry, value: initial)

    Locksmith.write(cache, [ key ], fn ->
      existed = Exists.execute(cache, key, const(:notify_false))

      try do
        name
        |> :ets.update_counter(key, entry_mod({ :value, amount }), default)
        |> handle_existed(existed)
      rescue
        _ -> error(:non_numeric_value)
      end
    end)
  end

  ###############
  # Private API #
  ###############

  # Handles the normalization of an incremented value.
  #
  # If the value already existed we return an `:ok` tag,
  # otherwise we return a `:missing` tag.
  defp handle_existed(val, { :ok, true }),
    do: { :ok, val }
  defp handle_existed(val, { :ok, false }),
    do: { :missing, val }
end
