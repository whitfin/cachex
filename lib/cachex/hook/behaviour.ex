defmodule Cachex.Hook.Behaviour do
  @moduledoc false
  # Provides the behaviour implementations for a Cachex Hook. At this point in
  # time we just enforce a handle_notify implementation which takes the event,
  # a potential results object, and the state of your Hook.

  @doc """
  The basic implementation of a hook notification. This two-arg implementation
  will receive the notification (i.e. the action), as well as the state of your
  hook. Input tuples will always be of the format `{ :action, args... }`, and
  the state is totally controlled by the user (as with any GenServer-type proc).
  """
  @callback handle_notify(tuple, any) :: { :ok, any }

  @doc """
  This implementation is the same as `handle_notify/2`, except we also provide
  the results of the action as the second argument. This is only called if the
  `results` key is set to a truthy value inside your Cachex.Hook struct.
  """
  @callback handle_notify(tuple, tuple, any) :: { :ok, any }
end
