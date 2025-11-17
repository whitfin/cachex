# Custom Commands

Cachex allows for custom commands to be attached to a cache, in order to simplify common logic without having to channel all of your cache calls through a specific block of code or a specific module. Cache commands are the solution for extending Cachex with operations or verbiage specific to your application and/or domain without bloating Cachex itself.

Commands operate in such a way that they're marginally quicker than hand-writing your own wrapper functions, but only very slightly. As a rule of thumb you should aim to set only very general actions as commands on a cache, and keep very specific actions outside of the caching layer. It's possible that in future Cachex may ship with some additional built-in commands for very common functionality (perhaps as a separate library).

## Defining a Command

Commands are defined on a per-cache basis via the `:commands` flag inside the `Cachex.start_link/2` options.

There are two types of command, either `:read` or `:write`. As you might guess the former will return a modified value from within a cache, while the latter will modify the value inside the cache before returning it.

Let's consider some basic `List` operations, and assume that we're storing some `List` types in a cache. In this case we might wish to have some typical `List` operations attached to our cache, rather than defining them externally.

Two perfect examples for us to look at are retrieving the last item in a list (`List.last/1`), and also popping the first item from a list (`List.pop_at/3` with index 0). As the former does not need to modify the `List`, it would be classed as a `:read` command. In contrast the latter _does_ need to modify the `List`, and so it would be classed as a `:write` command.

Let's look at how we can define simple versions of these commands and attach them to a cache at startup:

```elixir
# need the records
import Cachex.Spec

# define some custom commands
last = &List.last/1
lpop = fn
  ([ head | tail ]) ->
    { head, tail }
  ([ ] = list) ->
    {  nil, list }
end

# attach them to the cache
Cachex.start_link(:my_cache, [
  commands: [
    last: command(type:  :read, execute: last),
    lpop: command(type: :write, execute: lpop)
  ]
])
```

Each command receives a cache value to operate on an return. A command flagged as `:read` will simply transform the cache value before it's returned the user, allowing a developer to mask complicated logic directly in the cache itself rather than the calling module. This is suitable for storing specific structures in your cache and allowing "direct" operations on them (i.e. lists, maps, etc.).

Commands flagged as `:write` as a little more complicated, but still fairly easy to grasp. These commands *must* always resolve to a 2 element tuple, with the value to return from the call at index `0` and the new cache value in index `1`. You can either return a 2 element tuple as-is, or it can be contained in the `:commit` interfaces of Cachex:

```elixir
lpop = fn
  ([ head | tail ]) ->
    {:commit, {head, tail}}
  (_) ->
    {:ignore, nil}
end
```

This provides uniform handling across other cache interfaces, and makes it possible to implement things like lazy loading while providing an escape for the developer in cases where writing should be skipped. This is not perfect, so behaviour here may change in future as new options become available.

## Invoking Commands

The entry point to command invocation is via the `Cachex.invoke/4` interface function. This function accepts a command name and the key it should be called on. All value retrieval is handled automatically, and errors like invalid command names will result in an error as expected.

Let's look at some examples of calling the new `:last` and `:lpop` commands we defined above, after populating an example list in our cache.

```elixir
# place a new list into our cache of 3 elements
{ :ok, true } = Cachex.put(:my_cache, "my_list", [ 1, 2, 3 ])

# check the last value in the list stored under "my_list"
{ :ok,    3 } = Cachex.invoke(:my_cache, :last, "my_list")

# pop all values from the list stored under "my_list"
{ :ok,    1 } = Cachex.invoke(:my_cache, :lpop, "my_list")
{ :ok,    2 } = Cachex.invoke(:my_cache, :lpop, "my_list")
{ :ok,    3 } = Cachex.invoke(:my_cache, :lpop, "my_list")
{ :ok,  nil } = Cachex.invoke(:my_cache, :lpop, "my_list")

# check the last value in the list stored under "my_list"
{ :ok,  nil } = Cachex.invoke(:my_cache, :last, "my_list")
```

We can see how both commands are doing their job and we're left with an empty list at the end of this snippet. At the time of writing there are no options recognised by `Cachex.invoke/4` even though there _is_ an optional fourth parameter for options, it's simply future proofing.

This example does highlight one shortcoming that custom commands do have currently; it's not possible to remove an entry from the table inside a custom command yet. This may be supported in future but there's currently no real demand, and adding it would complicate the interface so it's on pause for now.
