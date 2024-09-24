defmodule Cachex.Actions.Incr do
  @moduledoc false
  # Command module to enable incrementing cache entries.
  #
  # This operates on an ETS level for the actual update calls, rather than using
  # a transactional context. The result is a faster throughput with the same
  # behaviour aspects (but we still lock the key temporarily).
  alias Cachex.Options
  alias Cachex.Services.Janitor
  alias Cachex.Services.Locksmith

  # we need some imports
  import Cachex.Spec
  import Cachex.Error

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
  def execute(cache(name: name) = cache, key, amount, options) do
    modify = entry_mod({:value, amount})

    default =
      entry_now(
        key: key,
        value: Options.get(options, :default, &is_integer/1, 0),
        expiration: Janitor.expiration(cache, nil)
      )

    Locksmith.write(cache, [key], fn ->
      try do
        {:ok, :ets.update_counter(name, key, modify, default)}
      rescue
        _ -> error(:non_numeric_value)
      end
    end)
  end
end
