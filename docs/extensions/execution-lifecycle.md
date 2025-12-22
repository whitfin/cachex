# Execution Lifecycle

Sometimes it might be beneficial to hook into when cache actions occur, and so Cachx provides a way to do so. This is avaiable via the hook system, which allows the developer to specify execution hooks which are notified when actions are carried out. These execution hooks receive messages in the form of tuples, which represent the action taken by the cache and also potentially the result of the action.

## Creating a Hook

Cachex provides a behaviour `Cachex.Hook` which provides a small abstraction over `GenServer`, with a few tweaks around synchronous execution and argument handling. All cache notifications can be received via `handle_notify/3`, but you still have access to all of the usual `GenServer` callbacks in case you want to add any additional logic to your hook (which is very common).

Hooks can become quite complicated, but let's look at a simple example of logging all cache actions to `:stdout` and keeping track of the last cache action executed. As stated above we have access to all the usual `GenServer` callbacks, so we can define a `handle_call/3` callback to retrieve any data we need:

```elixir
defmodule MyProject.MyHook do
  @moduledoc """
  A small hook to log all actions and store the most recent.
  """
  use Cachex.Hook

  # Initialization.
  def init(_),
    do: { :ok, nil }

  # Log the action and result, then store the action.
  def handle_notify(action, result, _last) do
    IO.puts("Action: #{action}")
    IO.puts("Result: #{result}")
    { :ok, action }
  end

  # Provide access to the last executed cache action.
  def handle_call(:last_action, _ctx, last),
    do: { :reply, last, last }
end
```

Once you have your `Cachex.Hook` definition, you can attach it to a cache a startup using the `:hooks` option on the `Cachex.start_link/2` interface. This option accepts a list of `Cachex.Spec.hook` records and attaches them to the cache on launch:

```elixir
# need the records
import Cachex.Spec

# create a cache with our hook
Cachex.start_link(:my_cache, [
  hooks: [
    hook(module: MyProject.MyHook)
  ]
])
```

A minimal hook record will contain just the name of the module implementing the `Cachex.Hook` behaviour, but you can also provide an initial `:state` (defaults to `nil`) and a custom `:name` for the hook process (which defaults to the process identifier). Please see the `Cachex.Hook` documentation for the optional callbacks which can be implemented to configure your hook.

## Notification Types

Each hook notification consists of the name of the cache action being executed, and the list of arguments it was called with. These notifications are of the form `{ action, args }` where `action` is an atom action name and `args` is a list of execution arguments.

Below is an example just to show this in context of a cache call, assuming we're doing a simple `Cachex.get/3` call:

```elixir
# given this cache call and result
"value" = Cachex.get(:my_cache, "key")

# you would receive these notification params
{ :get, [ :my_cache, "key" ], "value" }
```

Using this pattern makes it simple to hook into specific actions or specific cases (such as error cases), which is a powerful tool enabled by a very simple interface.

## Provisioning Hooks

There are some specific values which cannot be provided to your hook on startup as they have not yet been created. The best and most useful example of this is the cache's inner state, as it allows cache calls without the overhead of looking up the cache location each time.

The `provisions/0` callback can be used to gain access to such values, by returning a `List` of atoms to signal which items should be provided to your hook. This option will cause your hook to be provided with an instance of what you're asking for, via the `handle_provision/2` callback. An example of this pattern looks like this:

```elixir
defmodule MyProject.MyHook do
  use Cachex.Hook

  # Initialization.
  def init(_),
    do: { :ok, nil }

  # Request the cache state as a provision.
  def provisions,
    do: [ :cache ]

  # Receive a cache state and store it for later.
  def handle_provision({ :cache, cache }, _cache),
    do: { :noreply, cache }
end
```

The message received inside `handle_provision/2` will be of the form `{ type, value }` where `type` is equal to the atom you've requested (in this case `:cache`). Be aware that this modification event may be fired multiple times if the provided value is modified elsewhere, in order to keep hooks in sync with internal changes. Please see `Cachex.Provision` for details on the provisioning behaviour and the available options.

## Performance Overhead

Although hooks have been fairly well optimized at this point, there is still a minimal overhead to defining a hook.

If you are using an asynchronous hook, the overhead to the main cache execution flow is only the cost of passing a message to the backing hook process. This is extremely minimal and should pale in comparison to your main application logic, and likely be near irrelevant. In the case of synchronous hooks, we still have this same message passing overhead but of course the logic taken inside the hook itself has an impact on the execution flow.

As the typical use case for cache hooks is only one or two asynchronous hooks, the notification flow is optimized for this scenario. For this reason it's important to note that hooks are always notified sequentially, as spawning a process per hook would be a dramatic slowdown for asynchronous hoks. This should be kept in mind when using synchronous hooks, as (for example) 5 synchronous hooks each taking 1 second to run would result in a 5 second execution time for a cache call. This isn't necessarily bad if your usage pattern allows for it, but it's something to be aware of.

