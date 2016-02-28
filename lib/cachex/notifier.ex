defmodule Cachex.Notifier do
  @moduledoc false
  # A very small notification module to send data to a listening payload. This
  # data should be in the form of a tuple, and the data should be arguments which
  # were sent alongside a function call in the worker.

  alias Cachex.Options
  alias Cachex.Util
  alias Cachex.Worker

  @doc """
  Notifies a listener of the passed in data. If the data is a list, we convert it
  to a tuple in order to make it easier to pattern match against. We accept a list
  of listeners in order to allow for multiple (plugin style) listeners. This might
  never be utilised but it's easy to support it.
  """
  def notify(_state, _block, _action, _result \\ nil)
  def notify(%Worker{ options: %Options{ listeners: [] } } = state, _block, _action, _result) do
    state
  end
  def notify(state, block, action, result) when is_list(action) do
    notify(state, block, Util.list_to_tuple(action), result)
  end
  def notify(state, :pre, action, _result) do
    emit(state, :pre, action)
  end
  def notify(state, :post, action, result) do
    emit(state, :post, { action, result })
  end

  # Emits the given payload to all required listeners in the state. This just
  # strips out some code duplication.
  defp emit(state, block, payload) do
    state.options.listeners
    |> Stream.filter(&(elem(&1, 1) == block))
    |> Enum.each(fn
        ({ ref, ^block, :sync }) -> GenEvent.sync_notify(ref, payload)
        ({ ref, ^block, _sync }) -> GenEvent.notify(ref, payload)
       end)
    state
  end

end
