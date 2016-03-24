defmodule Cachex.Notifier do
  # require the Logger
  require Logger

  @moduledoc false
  # A very small notification module to send data to a listening payload. This
  # data should be in the form of a tuple, and the data should be arguments which
  # were sent alongside a function call in the worker.

  # add some aliases
  alias Cachex.Hook

  @doc """
  Notifies a listener of the passed in data. If the data is a list, we convert it
  to a tuple in order to make it easier to pattern match against. We accept a list
  of listeners in order to allow for multiple (plugin style) listeners. Initially
  had the empty clause at the top but this way is better (at the very worst it's
  the same performance).
  """
  def notify(_hooks, _action, _results \\ nil)
  def notify([hook|tail], action, results) do
    emit(hook, action, results)
    notify(tail, action, results)
  end
  def notify([], _action, _results), do: nil

  # Internal emission, used to define whether we send using an async request or
  # not. We also determine whether to pass the results back at this point or not.
  # This only happens for post-hooks, and if the results have been requested. We
  # skip the overhead in GenEvent and go straight to `send/2` to gain all speed
  # possible here.
  defp emit(hook, action, results) do
    cond do
      hook.ref == nil ->
        nil
      hook.results and hook.type == :post ->
        emit(hook, { action, results })
      true ->
        emit(hook, action)
    end
  end
  defp emit(%Hook{ "async": true, "ref": ref }, payload) do
    send(ref, { :notify, { :async, payload } })
  end
  defp emit(%Hook{ "async": false } = hook, payload) do
    send(hook.ref, { :notify, { :sync, self, payload } })
    receive do
      _ -> nil
    after
      hook.max_timeout -> nil
    end
  end
  defp emit(_, _action), do: nil

end
