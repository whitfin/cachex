defmodule Cachex.Actions.Get do

  alias Cachex.Actions
  alias Cachex.Actions.Set
  alias Cachex.State
  alias Cachex.Util

  def execute(%State{ } = state, key, options \\ []) when is_list(options) do
    Actions.do_action(state, { :get, [ key, options ] }, fn ->
      state
      |> Actions.read(key)
      |> handle_record(state, key, options)
    end)
  end

  defp handle_record({ key, _touched, _ttl, value }, _state, key, _opts) do
    { :ok, value }
  end
  defp handle_record(_missing, state, key, opts) do
    fallb = Util.get_opt_function(opts, :fallback)

    state
    |> Util.get_fallback(key, fallb)
    |> handle_fallback(state, key, opts)
  end

  defp handle_fallback({ :ok, value }, _state, _key, _opts) do
    { :missing, value }
  end
  defp handle_fallback({ :loaded, value } = res, state, key, opts) do
    Set.execute(state, key, value, Keyword.take(opts, [ :notify ]))
    res
  end

end
