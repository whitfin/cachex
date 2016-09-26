defmodule Cachex.Actions.Get do
  @moduledoc false
  # This module provides the implementation for the Get action, which is in charge
  # of retrieving values from the cache by key. If the record has expired, it is
  # purged on read. If the record is missing, we allow the use of fallback functions
  # to populate a new value in the cache.

  # we need our imports
  use Cachex.Actions

  # add some aliases
  alias Cachex.Actions
  alias Cachex.Actions.Set
  alias Cachex.State
  alias Cachex.Util

  @doc """
  Retrieves a value from inside the cache.

  This action supports the ability to fallback to another cache or computation
  to load any missing values. If the value does not exist in the cache, fallbacks
  can be used to set the value in the cache for next time. Note that `nil` values
  inside the cache are treated as missing values.
  """
  defaction get(%State{ } = state, key, options) do
    state
    |> Actions.read(key)
    |> handle_record(state, key, options)
  end

  # Handles the return record from the cache. If the record exists, we just skip
  # ahead and return the value by itself. If the record doesn't exist, we attempt
  # to load it using any provided fallback functions, otherwise we settle for
  # returning a nil value at this point.
  defp handle_record({ key, _touched, _ttl, value }, _state, key, _opts) do
    { :ok, value }
  end
  defp handle_record(_missing, state, key, opts) do
    fallb = Util.get_opt(opts, :fallback, &is_function/1)

    state
    |> Util.get_fallback(key, fallb, nil)
    |> handle_fallback(state, key, opts)
  end

  # Handles the result of a potential fallback. If the fallback receives a nil
  # value, we've missing the cache and haven't been able to load anything so we
  # just return nil and stop. If we have received a fallback, then we make sure
  # to set the value inside the cache so that it can be hit first try next time.
  defp handle_fallback({ :default, val }, _state, _key, _opts),
    do: { :missing, val }
  defp handle_fallback({ :ignore, val }, _state, _key, _opts),
    do: { :loaded, val }
  defp handle_fallback({ :commit, val }, state, key, opts) do
    note_opt = Enum.find(opts, [], &find_notify/1)
    set_opts = List.wrap(note_opt)

    Set.execute(state, key, val, set_opts)

    { :loaded, val }
  end

  # Simply returns true only if the option key is `:notify`.
  defp find_notify({ :notify, _value }), do: true
  defp find_notify({ _option, _value }), do: false

end
