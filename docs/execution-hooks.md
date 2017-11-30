# Execution Hooks

Sometimes you might want to hook into cache actions and so Cachex provides a way do to just that via the hook system, which essentially allows the user to specify execution hooks which are notified when actions are carried out. These hooks receive messages in the form of Tuples representing the action taken which triggered the hook, in the form of `{ action, action_args }` where `action` represents the name of the function being executed (as an atom) and `action_args` represents the arguments provided to the function (as a List). Here is an example just to show this in context of a cache call, assuming we're doing a simple `get/3` call:

```elixir
# given this cache call
Cachex.get(:my_cache, "key")

# you would receive this notification
{ :get, [ :my_cache, "key" ] }
```

Due to the way Hooks are implemented and notified internally, there is only a very minimal overhead to defining a Hook (usually around a microsecond per definition) however if you define a synchronous hook then the performance depends entirely on the actions taken inside. It should also be noted that Hooks are always notified sequentially as spawning a process per hook is a dramatic slowdown for asynchronous hooks. You should keep this in mind when using synchronous hooks as N hooks which all take a second to execute will cause the cache call to take at least N seconds before completing.

## Creating Hooks

Hooks are a small abstraction over the existing `GenServer` which ships with Elixir, mainly with a few tweaks around synchronous execution and argument handling. As such all notifications are handled via `handle_notify/3` (demonstrated below), but you also have action to all of the usual `GenServer` callbacks in case you need to add custom logic.

Hooks can be complicated, but here is a simple hook definition which simply logs all cache actions to `:stdout` and keeps track of the last action executed. Notifications are received in the `handle_notify/3` callback and then stored in the state to keep track of the latest action. As we're using `GenServer` we can just define a `handle_call/3` callback which allows us to retrieve the last action with the usual `GenServer.call/3` function.

```elixir
defmodule MyProject.MyHook do
  use Cachex.Hook

  @moduledoc """
  A very small example hook which simply logs all actions to stdout and keeps
  track of the last executed action.
  """

  @doc """
  The arguments provided to this function are those defined in the `args` key of
  your hook registration. This is the same as any old GenServer init phase. The
  value you return in the Tuple will be the state of your hook.
  """
  def init([]),
    do: { :ok, nil }

  @doc """
  This is the actual handler of your hook, receiving a message, results and the
  state. If the hook is a of type `:pre`, then the results will always be `nil`.

  Messages take the form `{ :action, [ args ] }`, so you can quite easily pattern
  match and take different action based on different events (or ignore certain
  events entirely).

  The return type of this function should be `{ :ok, new_state }`, anything else
  is not accepted.
  """
  def handle_notify(msg, results, _last) do
    IO.puts("Message: #{msg}")
    IO.puts("Results: #{results}")
    { :ok, msg }
  end

  @doc """
  Provides a way to retrieve the last action taken inside the cache.
  """
  def handle_call(:last_action, _ctx, last),
    do: { :reply, last, last }
end
```

Once you have your Hook definition you can attach it to the cache at startup using the `:hooks` option on the `start_link/3` interface. This essentially accepts a list of `hook` records and attaches them to the cache on launch. These structs store various options associated with Hooks alongside a listener module, which are documented below (although make sure to check the module documentation to see the latest options). Of the options listed only `module` is a require argument as there's clearly no way to default that. In addition it should be noted that `timeout` has no effect if the hook is not being executed in a synchronous fashion.

|   Option  |       Values       | Default |                          Description                           |
|:---------:|:------------------:|:-------:|:--------------------------------------------------------------:|
|    args   |        any         |   `[]`  |      Arguments to pass to the initialization of your hook.     |
|   async   | `true` or `false`  |  `true` |     Whether or not this hook should execute asynchronously.    |
|   module  | a module definition|  `nil`  | A module containing your which implements the Hook interface.  |
|  options  |        any         |   `[]`  |              Arguments to pass to the GenServer.               |
|  provide  |    list of atoms   |   `[]`  |      A list of post-startup values to provide to your hook.    |
|  timeout  | no. of milliseconds|  `nil`  | A maximum time to wait for your synchronous hook to complete.  |
|   type    | `:pre` or `:post`  | `:post` |   Whether this hook should execute before or after the action. |

## Provisions

There are some cache specific values which cannot be granted to your Hook on startup as they haven't yet been created. One big example is the cache inner state, as it allows cache calls without the overhead of looking up state each time. In `v1.0.0` a `:provide` option was added to the Hook interface which takes a List of atoms to specify various things to be provided to your Hook. This option will cause your Hook to be provided with an instance of what you're asking for via the `handle_provision/2` callback.

```elixir
defmodule MyProject.MyHook do
  use Cachex.Hook

  @doc """
  Initialize with a simple map to store values inside your hook.
  """
  def init([]),
    do: { :ok, %{ } }

  @doc """
  Handle the modification event, and store the cache state as needed inside your
  state. This state can be passed to the main Cachex interface in order to call
  the cache from inside your hooks.
  """
  def handle_provision({ :cache, cache_state }, state),
    do: { :noreply, Map.put(state, :cache, cache_state) }
end
```

The message you receive in `handle_provision/2` will always be `{ provide_option, value }` where `provide_option` is equal to the atom you've asked for (in this case `:cache`). Be aware that this modification event may be fired multiple times if the internal worker structure has changed for any reason.
