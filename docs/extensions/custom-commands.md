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

Each command receives a cache value to operate on and return. A command flagged as `:read` (such as `:last` above) will simply transforms the cache value before the final command return occurs, allowing the cache to mask complicated logic from the calling module. Commands flagged as `:write` are a little more complicated, but still fairly easy to grasp. These commands *must* return a 2-element tuple, with the return value in index `0` and the new cache value in index `1`.

It is important to note that custom cache commands _will_ receive `nil` values in the cache of a missing cache key. If you're using a `:write` command and receive a misisng value, your returned modified value will only be written back to the cache if it's no longer `nil`. This allows the developer to implement logic such as lazy loading, but also escape the situation where you're cornered into writing to the cache.

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

