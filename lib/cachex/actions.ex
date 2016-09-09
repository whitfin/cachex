defmodule Cachex.Actions do
  @moduledoc false

  alias Cachex.Actions.Del
  alias Cachex.Notifier
  alias Cachex.State
  alias Cachex.Util

  # define purge constants
  @purge_override [{ :via, { :purge, [[]] } }, { :hook_result, { :ok, 1 } }]

  @doc """
  Handler for broadcasting a set of actions and results to all registered hooks.
  This is fired by out-of-proc calls (i.e. Janitors) which need to notify hooks.
  """
  def broadcast(%State{ } = state, action, result) do
    do_action(state, action, fn -> result end)
  end
  def broadcast(cache, action, result) when is_atom(cache) do
    case State.get(cache) do
      nil -> false
      val -> broadcast(val, action, result)
    end
  end

  # Forwards a call to the correct actions set, currently only the local actions.
  # The idea is that in future this will delegate to distributed implementations,
  # so it has been built out in advance to provide a clear migration path.
  def do_action(%State{ } = state, { _act, opts } = msg, fun) when is_function(fun) do
    options = List.last(opts)
    notify  = Keyword.get(options, :notify, true)

    message = case options[:via] do
      nil -> msg
      val when is_tuple(val) -> val
      val -> put_elem(msg, 0, val)
    end

    if notify do
      case state.pre_hooks do
        [] -> nil;
        li -> Notifier.notify(li, message)
      end
    end

    result = fun.()

    if notify do
      case state.post_hooks do
        [] -> nil;
        li -> Notifier.notify(li, message, options[:hook_result] || result)
      end
    end

    result
  end

  @doc """
  Writes a record into the cache, and returns a result signifying whether the
  write was successful or not.
  """
  @spec write(state :: State.t, record :: Record.t) :: { :ok, true | false }
  def write(%State{ cache: cache }, record) do
    { :ok, :ets.insert(cache, record) }
  end

  @doc """
  Reads back a key from the cache.

  If the key does not exist we return a `nil` value. If the key has expired, we
  delete it from the cache using the `:purge` action as a notification.
  """
  @spec read(state :: State.t, key :: any) :: Record.t | nil
  def read(%{ cache: cache } = state, key) do
    cache
    |> :ets.lookup(key)
    |> handle_read(state)
  end

  defp handle_read([{ key, touched, ttl, _value } = record], state) do
    if Util.has_expired?(state, touched, ttl) do
      Del.execute(state, key, @purge_override)
      nil
    else
      record
    end
  end
  defp handle_read(_missing, _state) do
    nil
  end

  @doc """
  Updates a number of fields in a record inside the cache, by key.

  For ETS, we do this entirely in a single sweep. For Mnesia, we need to use a
  two-step get/update from the Worker interface to accomplish the same. We then
  use a reduction to modify the Tuple.
  """
  @spec update(state :: State.t, key :: any, changes :: [{}]) :: { :ok, true | false }
  def update(%State{ cache: cache }, key, changes) do
    cache
    |> :ets.update_element(key, changes)
    |> handle_update
  end

  defp handle_update( true), do: { :ok, true }
  defp handle_update(false), do: { :missing, false }

end
