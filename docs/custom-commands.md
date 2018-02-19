# Custom Commands

As of `v2.0.0` Cachex allows custom commands to be attached to a cache in order to simplify common logic without having to channel all of your cache calls through a specific block of code or a specific module. Cache commands are provided in order to make it easier to extend Cachex with operations or verbiage specific to your application logic, rather than bloating Cachex itself with commands which are only needed for infrequent use cases.

Commands operate in such a way that they're marginally quicker than hand-writing your own wrapper functions, but only very slightly. As a rule of thumb you should aim to set only general actions as commands on a cache, whilst keeping very specific actions outside of the cache. It's possible that in future Cachex may ship with some built-in commands for very common functionality.

## Defining Commands

Commands are defined on a per-cache basis by using the `:command` flag inside the `start_link/3` options.

There are two types of commands; `:read` and `:write` commands. The former will return a value after your command executes, whilst the latter will modify the value before placing it back into the cache (and returning a value).

As an example, let's consider some basic List operations. Assume that the values you're storing in your cache are Lists, and that you want to be able to write the boilerplate required on your cache in order to retrieve the last item in the List, and to pop out the first item of the List. As the former doesn't modify the List, it would be classed as a `:read` command. In contrast, the latter does need to modify the List and so it's tagged as a `:write` operation:

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

Each command (regardless of the type of command) receives a cache value to operate on and return. A command tagged with `:read` (such as `:last` above) will simply transforms the cache value before the final command return occurs, allowing the cache to mask complicated logic from the calling module.

The `:write` command type is a little more complicated but still fairly easy to grasp. Essentially these commands *must* return a 2-element Tuple, with the return value on the left and the new cache value on the right. Consider a return value of `{ 1, 2 }`; `1` would be the return value of your cache call, and `2` would be the new value set inside the cache. Currently this format is required in order to be explicit as to what you wish to do with your values as it's not intuitive as to what action the cache should take otherwise.

It should be noted that custom commands can and will receive `nil` values in the case of a missing key. If you're using a `:write` command and receive a missing value, your modified value will only be written back to the cache if it's not still `nil` - this is to allow you to basically escape the situation where you're forced to write something to the cache.

## Invoking A Command

Your entry point to command invocation is via the `Cachex.invoke/4` interface, which has the signature `(cache, command, key, options)`. The command argument is just the name of your custom command (as you tagged it at cache startup), and the key is the key you wish to run your command against - value retrieval is handled automatically. Invalid command names will result in an error, as you would expect. The example below should give you a good introduction on how to call your own commands inside your application.

```elixir
import Cachex.Spec

lpop = fn
  ([ head | tail ]) ->
    { head, tail }
  ([ ] = list) ->
    {  nil, list }
end

Cachex.start_link(:my_cache, [
  commands: [ lpop: command(type: :write, execute: lpop) ]
])

{ :ok, true } = Cachex.put(:my_cache, "my_list", [ 1, 2, 3 ])
{ :ok,    1 } = Cachex.invoke(:my_cache, :lpop,  "my_list")
{ :ok,    2 } = Cachex.invoke(:my_cache, :lpop,  "my_list")
{ :ok,    3 } = Cachex.invoke(:my_cache, :lpop,  "my_list")
{ :ok,  nil } = Cachex.invoke(:my_cache, :lpop,  "my_list")
```
