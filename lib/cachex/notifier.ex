defmodule Cachex.Notifier do
  @moduledoc false
  # A very small notification module to send data to a listening payload. This
  # data should be in the form of a tuple, and the data should be arguments which
  # were sent alongside a function call in the worker.

  @doc """
  Notifies a listener of the passed in data. If the data is a list, we convert it
  to a tuple in order to make it easier to pattern match against. We accept a list
  of listeners in order to allow for multiple (plugin style) listeners. Initially
  had the empty clause at the top but this way is better (at the very worst it's
  the same performance).
  """
  def notify([listener|tail], action) do
    emit(listener, action)
    notify(tail, action)
  end
  def notify([], _action), do: nil

  # Internal emission, used to define whether we send using an async request or
  # not. We use `send/2` directly to avoid the wasted overheard in the GenEvent
  # module (we always use the same implementation).
  defp emit({ ref, _, :async }, action),
  do: send(ref, { :notify, action })
  defp emit({ ref, _, :sync }, action),
  do: send(ref, { :sync_notify, action })
  defp emit(_, _action), do: nil

end
