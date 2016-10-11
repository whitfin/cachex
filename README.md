# Cachex
[![Coverage Status](https://img.shields.io/coveralls/zackehh/cachex/master.svg?maxAge=900000&style=flat-square)](https://coveralls.io/github/zackehh/cachex) [![Unix Build Status](https://img.shields.io/travis/zackehh/cachex/master.svg?maxAge=900000&label=unix&style=flat-square)](https://travis-ci.org/zackehh/cachex) [![Windows Build Status](https://img.shields.io/appveyor/ci/zackehh/cachex/master.svg?maxAge=900000&label=windows&style=flat-square)](https://ci.appveyor.com/project/zackehh/cachex) [![Hex.pm Version](https://img.shields.io/hexpm/v/cachex.svg?maxAge=900000&style=flat-square)](https://hex.pm/packages/cachex) [![Documentation](https://img.shields.io/badge/docs-latest-blue.svg?style=flat-square)](https://hexdocs.pm/cachex/)

Cachex is an extremely fast in-memory key/value store with support for many useful features:

- Time-based key expirations
- Maximum size protection
- Pre/post execution hooks
- Statistics gathering
- Multi-layered caching/key fallbacks
- Transactions and row locking
- Asynchronous write operations
- User command invocation

All of these features are optional and are off by default so you can pick and choose those you wish to enable.

## Table of Contents

- [Installation](#installation)
- [Usage](#usage)
    - [Startup](#startup)
    - [Interface](#interface)
    - [Options](#options)
- [Migrating To v2.x](#migrating-to-v2)
- [Action Blocks](#action-blocks)
    - [Execution Blocks](#execution-blocks)
    - [Transaction Blocks](#transaction-blocks)
    - [Things To Remember](#things-to-remember)
- [Cache Limits](#cache-limits)
    - [Limit Structures](#limit-structures)
- [Custom Commands](#custom-commands)
    - [Definition](#command-definition)
    - [Invocation](#command-invocation)
- [Execution Hooks](#execution-hooks)
    - [Definition](#hook-definition)
    - [Registration](#hook-registration)
    - [Provisions](#hook-provisions)
    - [Performance](#hook-performance)
- [Multi-Layered Caches](#multi-layered-caches)
    - [Common Fallbacks](#common-fallbacks)
    - [Specified Fallbacks](#specified-fallbacks)
- [TTL Implementation](#ttl-implementation)
    - [Janitor Processes](#janitor-processes)
    - [On Demand Expiration](#on-demand-expiration)
- [Benchmarks](#benchmarks)
- [Contributions](#contributions)

## Installation

As of v0.8.0, Cachex is available on [Hex](https://hex.pm/). You can install the package via:

  1. Add cachex to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:cachex, "~> 1.2"}]
    end
    ```

  2. Ensure cachex is started before your application:

    ```elixir
    def application do
      [applications: [:cachex]]
    end
    ```

## Usage

#### Startup

The typical use of Cachex is to set up using a Supervisor, so that it can be handled automatically:

```elixir
Supervisor.start_link(
  [
    worker(Cachex, [:my_cache, []])
  ]
)
```

If you wish to start it manually (for example, in `iex`), you can just use `Cachex.start_link/2`:

```elixir
Cachex.start_link(:my_cache, [])
```

Although this is possible and is functionally the same internally, it's probably better to set up the supervision tree for fault-tolerance. As shown in the above examples, the only **required** option is the `name` option. This is the name of your cache and is how you will typically refer to the cache in the `Cachex` module.

#### Interface

The Cachex interface should/will be maintained such that it follows this pattern:

```elixir
Cachex.action(:my_cache, _required_args, _options \\ [])
```

Every action has a certain number of required arguments (can be `0`), and accepts a keyword list of options. As an example, here's how a `set` action could look:

```elixir
Cachex.set(:my_cache, "my_key", "my_value", [ ttl: :timer.seconds(5) ])
```

All actions should return a result in the format of `{ status, result }` where `status` is *usually* `:ok` or `:error`, however this is not required (for example, `Cachex.get/3` sometimes returns `{ :loaded, result }`). The second item in the tuple can be of any type and structure, and depends on the action being carried out.

All Cachex actions have an automatically generated unsafe equivalent, which unwraps these result tuples. This unwrapping assumes that `:error` status means that the result should be thrown, and that any other status should have the result returned alone.

Below is an example of this:

```elixir
iex(1)> Cachex.get(:my_cache, "key")
{:ok, nil}
iex(2)> Cachex.get!(:my_cache, "key")
nil
iex(3)> Cachex.get(:missing_cache, "key")
{:error, :no_cache}
iex(4)> Cachex.get!(:missing_cache, "key")
** (Cachex.ExecutionError) Specified cache not running
    (cachex) lib/cachex.ex:249: Cachex.get!/3
```

I'd typically recommend checking the values and using the safe version which gives you a tuple, but sometimes it's easier to use the unsafe version (for example in unit tests or when you're calling something which can't fail).

#### Options

Caches can accept a list of options during initialization, which determine various behaviour inside your cache. These options are defined on a per-cache basis and cannot be changed after being set.

|      Options     |       Values       |                               Description                               |
|:----------------:|:------------------:|:-----------------------------------------------------------------------:|
|     commands     |  list of commands  |   A list of custom commands to attach to the cache for invocation   |
|    default_ttl   |     milliseconds   | A default expiration time for a key when being placed inside the cache. |
|    disable_ode   |  `true` or `false` | Whether or not to disable on-demand expirations when reading back keys. |
|     ets_opts     |   list of options  |               A list of options to give to the ETS table.               |
|     fallback     |  Function or List  |   A function accepting a key which is used for multi-layered caching.   |
|       hooks      |    list of Hooks   |    A list of execution hooks (see below) to listen on cache actions.    |
|       limit      |  a Limit constuct  |     An integer or Limit struct to define the bounds of this cache.      |
|   record_stats   |  `true` or `false` |            Whether to track statistics for this cache or not.           |
|   transactions   |  `true` or `false` |             Whether to turn on transactions at cache start.             |
|   ttl_interval   |     milliseconds   |          The frequency the Janitor process runs at (see below).         |

For more information and examples, please see the official documentation on [Hex](https://hexdocs.pm/cachex/).

## Migrating To v2

There are a number of breaking changes in Cachex v2.0.0 for several reasons. Please read the [migration guide](https://github.com/zackehh/cachex/blob/master/MIGRATE.md) to learn about the changes and update your codebase. I tried to keep changes small, easy to learn, and only do them for the greater good, so there should be very little in a developer's codebase to modify (I hope).

## Action Blocks

As of `v0.9.0` support for execution blocks has been incorporated in Cachex. These blocks provide ways of ensuring many actions occur one after another (with some caveats, so read carefully). They come in two flavours; Execution Blocks and Transaction Blocks.

#### Execution Blocks

Execution Blocks were introduced to simply avoid the cost of passing state back and forth when it could be done in one step. For example, rather than:

```elixir
val1 = Cachex.get!(:my_cache, "key1")
val2 = Cachex.get!(:my_cache, "key2")
```

You can do something like this:

```elixir
{ val1, val2 } = Cachex.execute!(:my_cache, fn(state) ->
  v1 = Cachex.get!(worker, "key1")
  v2 = Cachex.get!(worker, "key2")
  { v1, v2 }
end)
```

Although this looks more complicated it saves you a read of the internal Cachex state, which actually trims off a large amount of the overhead of a Cachex request.

It should be noted that the consistency of these actions should not be relied upon. Even though you execute in a single block, you may still have cache actions occur between your calls inside the block. This is very important to keep in mind, and if this poses an issue, you might wish to move to [Transaction Blocks](#transaction-blocks) instead.

#### Transaction Blocks

Transaction Blocks are the consistent counterpart of Execution Blocks. They bind all actions into a transaction in order to ensure consistency even in distributed situations. This means that all actions you define in your transaction will execute one after another and are guaranteed successful. These blocks look almost identical to Execution Blocks, except that they require a list of keys to lock throughout their execution:

```elixir
{ val1, val2 } = Cachex.transaction!(:my_cache, [ "key1", "key2" ], fn(state) ->
  v1 = Cachex.set!(worker, "key1", 1)
  v2 = Cachex.set!(worker, "key2", 2)
  { v1, v2 }
end)
```

The major difference here is that it is guaranteed that no write operations occur on the locked keys whilst your transaction is executing. This means you can safely retrieve/modify/update values using custom logic without worrying that other processes are modifying your records in the meantime.

Of course it should be noted (and obvious) that transactions have quite a bit of overhead to them, so only use them when you have to (e.g. the example above should not be using them). The overhead is much less than previous iterations of Cachex due to an in-built lock table rather than going via Mnesia.

In addition, please note that transactions should only operate on the keys they have locked - if you write keys which haven't been locked, they're open to being written by external processes. This should always be checked appropriately when dealing with nested transactions.

#### Things To Remember

Hopefully you've noticed that in all examples above, we receive a `state` argument in our blocks. You **must** pass this to your `Cachex` calls, rather than the cache name. If you use the cache name inside your block, you lose all benefits of the block execution. Changes to Cachex in `v0.9.0` allow you to pass the `state` argument to the interface to safely avoid this issue.

## Cache Limits

There are currently two ways to define cache limits, currently based only around the number of entries in a cache (although this will change in future). You can provide either an integer, or a `Cachex.Limit` structure to the `:limit` option in the Cachex interface.

### Limit Structures

A Limit struct consists of currently only 3 fields which dictate a limit and how it should be enforced. This allows the user to customize their eviction without getting too low-level. For example, here is a basic Limit structure. This is what passing an integer as the `:limit` option to a cache would unpack to internally:

```elixir
%Cachex.Limit{
  limit: 500,
  policy: Cachex.Policy.LRW,
  reclaim: 0.1
}
```

This defines that the cache should aim to store no more than `500` entries. If the cache goes other this number, it should evict `50` of the oldest entries. The `50` is dictated by the `:reclaim` option which is a percentage of the cache to evict upon becoming maxed out. This value must fit `1 >= reclaim > 0` in order to be accepted.

The policy here is a built-in Cachex eviction policy which removes the oldest values first. This means that we calculate the first `N` oldest entries, where `N` is roughly equal to `limit * reclaim`, and remove them from the cache in order to make room for new entries. It should be noted that "oldest" here means "those written or updated longest ago".

This is currently the only policy implemented within Cachex, although more will follow. Here are a few examples of how they can be implemented against a cache:

```elixir
# maximum 500 entries, default eviction
Cachex.start(:my_cache1, [ limit: 500 ])

# maximum 500 entries, LRW eviction, trim 50%
Cachex.start(:my_cache2, [ limit: %Cachex.Limit{ limit: 500, policy: Cachex.Policy.LRW, reclaim: 0.5 } ])
```

You should be aware that eviction is not instant - it happens in reaction to events which are additive to the cache and is extremely quick, however if you have a cache limit of 500 keys and you add 500,000 keys, the cleanup does take a few hundred milliseconds to occur (that's a lot to clean). This shouldn't affect most users, but it is something to point out and be aware of.

It should be noted that although LRW is the only policy implemented at this time, you can control LRU policies by using `Cachex.touch/2` to do a write on a key without affecting the value or TTL. Using `Cachex.touch/2` and the LRW policy is likely how an LRU policy would work regardless.

## Custom Commands

As of v2.0.0, Cachex can have custom commands attached to a cache to simplify common logic without having to channel all of your cache calls through a specific module. Cache commands are provided in order to make it easy to extend Cachex with operations specific to your application logic, rather than bloating the library with commands that aren't always needed.

Commands operate in such a way that they're marginally quicker than hand-writing your own wrapper functions, but only very slightly. You should aim to set only general actions as cache commands, whilst keeping extremely custom actions outside of the cache. In future, Cachex may ship with some built in commands for common functionality.

Commands are defined on a per-cache basis, and you simply need to use the `:command` flag inside the `start_link/3` options to add your commands.

### Command Definition

There are two types of commands which can be added, `:return` commands and `:modify` commands - they should be self explanatory after looking at the example below. The former will return a value after your command transformation, whilst the latter will modify the value before placing it back into the cache. You can think of them as `read` and `write`, in effect.

As an example, let's consider some List operations. Below there are two commands defined on a cache; one to retrieve the last value inside a List, and the other to pop the first element from a List.

```elixir
last = &List.last/1
lpop = fn
  ([ head | tail ]) ->
    { head, tail }
  ([ ] = list) ->
    {  nil, list }
end

Cachex.start_link(:my_cache, [
  commands: [
    last: { :return, last },
    lpop: { :modify, lpop }
  ]
])
```

Retrieving the last item in a List is clearly just a read operation, and so we tag the command with a `:return` atom. This just means that whatever the `:last` command returns is returned, basically allowing you to transform cache values. This should be a very natural concept (I hope, at least).

The `:lpop` command is slightly more complicated, but provides a good example of the types of sugar you can implement with this interface. The return value of a `:modify` command **must** be a 2-element Tuple, with the return value on the left and the modified value on the right. For example, if you return a value of `{ 1, 2 }` then `1` would be the return type of your `invoke/4` call, and `2` would be the new value set inside the cache.

In the example above, we're simply "popping" the first element from the List - meaning that we're retrieving it whilst removing it at the same time. To do this, we return the `head` as the first element in the Tuple, and return the `tail` as the second element in the Tuple - thus easily allowing us to pop elements without having to do anything too fancy, and without code duplication.

I should mention that these command definitions are incredibly strict on purpose. If you don't provide a valid `{ :modify | :return, fun/1 }` syntax, you will receive an error. In addition, if your `:modify` function returns anything other than a 2-element Tuple, your app will crash (there is no good way to recover this).

Finally it should be noted that if your key is missing, you will be provided with a `nil` value. If you're using a `:modify` command and receive a missing value, your modified value will only be written to the cache if it is not `nil` - this is to avoid forcing you to write keys which were previously missing.

### Command Invocation

Your entry point to running a command is `Cachex.invoke/4`, which has the signature `(cache, key, command, options)`. The command is just the name of your custom command, and the key is the key you wish to run it against (simple enough). If you provide an invalid command name, you will receive an error. There are currently no options available, they're just provided as future proofing.

Below is an example of several invocations of the `:lpop` example as defined above. This should give you a good enough introduction on how to call your commands:

```elixir
lpop = fn
  ([ head | tail ]) ->
    { head, tail }
  ([ ] = list) ->
    {  nil, list }
end

Cachex.start_link(:my_cache, [
  commands: [ lpop: { :modify, lpop } ]
])

{ :ok, true } = Cachex.set(:my_cache, "my_list", [ 1, 2, 3 ])
{ :ok,    1 } = Cachex.invoke(:my_cache, "my_list", :lpop)
{ :ok,    2 } = Cachex.invoke(:my_cache, "my_list", :lpop)
{ :ok,    3 } = Cachex.invoke(:my_cache, "my_list", :lpop)
{ :ok,  nil } = Cachex.invoke(:my_cache, "my_list", :lpop)
```

## Execution Hooks

Cachex provides an easy way to plug into cache actions, by way of the hook system. This system allows the user to specify pre/post execution hooks which are notified when actions are taken.

These hooks accept messages in the form of tuples which represent the action being taken. These tuples basically represent `{ :action, action_args }`, where `:action` represents the name of the function being executed inside Cachex, and `action_args` represent the arguments provided to the function.

It's pretty straightforward, but in the interest of completeness, here is a quick example of how a Cachex command translates to the notification format:

```elixir
Cachex.get(:my_cache, "key") == { :get, [ :my_cache, "key" ] }
```

Cachex uses the typical `GenServer` pattern, and as such you get most of the typical interfaces. There are a couple of differences, but they're detailed below.

#### Hook Definition

Hooks are quite simply a small abstraction above the existing `GenServer` which ships with Elixir. Cachex tweaks a couple of minor things related to synchronous execution and argument format, but nothing too special. Below is an example of a very basic hook implementation:

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
  value you return in the tuple will be the state of your hook.
  """
  def init(options \\ []) do
    { :ok, nil }
  end

  @doc """
  This is the actual handler of your hook, receiving a message, results and the
  state. If the hook is a of type `:pre`, then the results will always be `nil`.

  Messages take the form `{ :action, args... }`, so you can quite easily pattern
  match and take different action based on different events (or ignore certain
  events entirely).

  The return type of this function should be `{ :ok, new_state }`, anything else
  is not accepted.
  """
  def handle_notify(msg, results, state) do
    IO.puts("Message: #{msg}")
    IO.puts("Results: #{results}")
    { :ok, msg }
  end

  @doc """
  Provides a way to retrieve the last action taken inside the cache.
  """
  def handle_call(:last_action, _ctx, state) do
    { :reply, state, state }
  end

end
```

As we're using a `GenServer`, you have access to all of the usual callback functions from the `GenServer` module. This is an improvement over v1.x, where only `GenEvent` functions were available. As such, make sure your `handle_call/3`, `handle_cast/2` and `handle_info/2` functions return appropriate values.

#### Hook Registration

To register hooks with Cachex, they must be passed in when setting up a cache in the call to `Cachex.start_link/3` (or in your Supervisor). This looks something like the following:

```elixir
defmodule MyModule do

  @on_load :init_cache

  def init_cache do
    my_hooks = [%Cachex.Hook{
      module: MyProject.MyHook,
      server_args: [ name: :my_project_hook ]
    }]
    { :ok, pid } = Cachex.start_link(:my_cache, [ hooks: my_hooks ])
    :ok
  end

end
```

A hook is an instance of the `%Cachex.Hook{}` struct. These structs store various options associated with hooks alongside a listener module and look similar to that shown below (the values used below are the defaults):

```elixir
%Cachex.Hook{
  args: [],
  async: true,
  max_timeout: nil,
  module: nil,
  provide: [],
  server_args: [],
  type: :post
}
```

These fields translate to the following:

|   Option  |       Values       |                          Description                           |
|:---------:|:------------------:|:--------------------------------------------------------------:|
|    args   |        any         |      Arguments to pass to the initialization of your hook.     |
|   async   | `true` or `false`  |     Whether or not this hook should execute asynchronously.    |
|max_timeout| no. of milliseconds| A maximum time to wait for your synchronous hook to complete.  |
|   module  | a module definition| A module containing your which implements the Hook interface.  |
|  provide  |    list of atoms   |      A list of post-startup values to provide to your hook.    |
|server_args|        any         |              Arguments to pass to the GenServer.               |
|   type    | `:pre` or `:post`  |   Whether this hook should execute before or after the action. |

**Notes**

- `max_timeout` has no effect if the hook is not being executed in a synchronous form.
- `module` is the only required argument, as there's no logical default to set if not provided.

#### Hook Provisions

There are some things which cannot be given to your hook on startup. For example if you wanted access to a cache worker in your hook, you would hit a dead end because all hooks are started before any worker processes. For this reason `v1.0.0` added a `:provide` option which takes a list of atoms which specify things to be provided to your hook.

For example, if you wish to call the cache safely from inside a hook, you're going to need a cache worker provisioned (much in the same way that [action blocks](#action-blocks) function). In order to retrieve this safely, your hook definition would implement a `handle_info/2` callback which looks something like this:

```elixir
defmodule MyProject.MyHook do
  use Cachex.Hook

  @doc """
  Initialize with a simple map to store values inside your hook.
  """
  def init([]) do
    { :ok, %{ } }
  end

  @doc """
  Handle the modification event, and store the cache worker as needed inside your
  state. This worker can be passed to the main Cachex interface in order to call
  the cache from inside your hooks.
  """
  def handle_info({ :provision, { :state, worker } }, state) do
    { :noreply, Map.put(state, :state, worker) }
  end
end
```

To then set up this hook, you need to make sure you tell the hook to be provisioned with a worker:

```elixir
hook = %Cachex.Hook{
  module: MyModule.WorkerHook,
  type: :post,
  provide: [ :worker ]
}
Cachex.start_link(:my_cache, [ hooks: hook ])
```

The message you receive in `handle_info/2` will always be `{ :provision, { provide_option, value } }` where `provide_option` is equal to the atom you've asked for (in this case `:state`). Be aware that this modification event may be fired multiple times if the internal worker structure has changed for any reason (for example when extra nodes are added to the cluster).

#### Hook Performance

Due to the way hooks are implemented and notified internally, there is only a very minimal overhead to defining a hook (usually around a microsecond per definition). Naturally if you define a synchronous hook then the performance depends entirely on the actions taken inside the hook (up until the timeout).

Hooks are always notified sequentially as spawning another process for each has far too much overhead, and so you should keep this in mind when using synchronous hooks as 3 hooks which all take a second to execute will cause the Cachex action to take at least 3 seconds before completing.

## Multi-Layered Caches

A very common use case (and one of the reasons I built Cachex) is the desire to have Multi-Layered Caches. Multi-layering is the idea of a backing cache (i.e. something remote) which populates your local caches on misses. A typical pattern is using [Redis](http://redis.io) as a remote data store and replicating it locally in-memory for faster access.

### Common Fallbacks

Let's look at an example;

Assume you have a backing Redis cache with a fairly large amount of keys, and you wish to cache it locally to avoid the network calls (let's say you're doing it thousands of times a second). Cachex can do this easily be providing a **fallback** action to take when a key is missing. This is configured during cache initialization using the `fallback` option, as below:

```elixir
# initialize the cache instance
{ :ok, pid } = Cachex.start_link(:redis_memory_layer, [ default_ttl: :timer.minutes(5), fallback: &RedisClient.get/1 ])

# status will equal :loaded if Redis was hit, otherwise :ok when successful
{ status, information } = Cachex.get(:redis_memory_layer, "my_key")
```

The use above will ensure that Cachex jumps to Redis to look for a key, **only if** it doesn't have a copy locally. If one does exist locally, Cachex will use that instead.

An effective approach with fallbacks is to use a TTL to make sure that your data doesn't become stale. In the case above, we can be sure that our data will never be more than 5 minutes out of date, whilst saving the impact of the network calls to Redis. Once a key expires locally after 5 minutes, Cachex will then jump back to Redis the next time the key is asked for. Of course the acceptable level of staleness depends on your use case, but generally this is a very useful behaviour as it allows applications to easily reap performance gains without sacrificing the ability to have a consistent backing store.

### Specified Fallbacks

You may have noticed that the above example assumes that all keys behave in the same way. Naturally this isn't the case, and so all commands which allow for fallbacks also allow overrides in the call itself.

Using another example, let's assume that you need to read information from a database to service a public API. The issue is that the query is expensive and so you want to cache it locally for 5 minutes to avoid overloading your database. To do this with Cachex, you would simply specify a TTL of 5 minutes on your cache, and use a fallback to read from your database.

```elixir
# initialize our database client
{ :ok, db } = initialize_database_client()

# initialize the cache instance
{ :ok, pid } = Cachex.start_link(:info_cache, [ default_ttl: :timer.minutes(5), fallback: [ state: db ] ])

# status will equal :loaded if the database was hit, otherwise :ok when successful
{ status, information } = Cachex.get(:info_cache, "/api/v1/packages", fallback: fn(key, db) ->
  Database.query_all_packages(db)
end)
```

The above is a multi-layered cache which only hits the database **at most** every 5 minutes, and hits local memory in the meantime (retrieving the exact same data as was returned from your database). This allows you to easily lower the pressure on your backing systems as the context of your call requires - for example in the use case above, we can totally ignore the key argument as the function is only ever invoked on that call.

Also note that this example demonstrates how you can provide state to your fallback functions by providing a Keyword List against the `:fallback` option. This list can contain the `:state` and `:action` keys to further customize how fallbacks work. The state is provided as a second argument to the action in the case it is not set to `nil`.

As demonstrated in the [Common Fallbacks](#common-fallbacks) section above, providing a function instead of a List is internally converted to `[ action: &RedisClient.get/1 ]`. It is simply shorthand in case you do not wish to provide a state.

## TTL Implementation

Cachex implements a few different ways of working with key expiration, namely the background TTL loop and on-demand key expiration. Separately these two techniques aren't enough to provide an efficient system as your keyspace would either grow too large due to keys not being accessed and purged on access, or you would be able to retrieve values which should have expired. Cachex opts for a combination of both in order to ensure consistency whilst also reducing pressure on things like table scans.

#### Janitor Processes

Cachex also enables a background process (nicknamed the `Janitor`) which will purge the internal table every so often. The Janitor operates using **full-table scans** and so you should be relatively careful about how often you run it. The interval that this process runs can be controlled, and Janitors exist on a per-cache basis (i.e. each cache has its own Janitor).

The Janitor is pretty well optimized; it can check and purge 500,000 expired keys in around a second (where the removal takes the most time, the check is very fast). As such, you're probably fine running it however often you wish but please keep in mind that running less frequently means you're not releasing the memory of expired keys. A typical use case is probably to run the Janitor every few seconds, and this is used as a default in a couple of places.

There are several rules to be aware of when setting up the interval:

- If you have `default_ttl` set in the cache options, and you have not set `ttl_interval`, the Janitor will default to running every 3 seconds. This is to avoid people forgetting to set it or simply being unaware that it's not running by default.
- If you set `ttl_interval` to `-1`, it is disabled entirely - even if you have a `default_ttl` set. This means you will be solely reliant on the on-demand expiration policy.
- If you set `ttl_interval` to `true`, it behaves the same way as if you had set a `default_ttl`; it will set the Janitor to run every 3 seconds.
- If you set `ttl_interval` to any numeric value above `0`, it will run on this schedule (this value is in milliseconds).

It should be noted that this is a rolling value which is set **on completion** of a run. This means that if you schedule the Janitor to run every 1ms, it will be 1ms after a successful run, rather than starting every 1ms. This may become configurable in the future if there's demand for it, but for now rolling seems to make the most sense.

#### On Demand Expiration

Keys have an internal touch time and TTL associated with them, and these values do not change unless triggered explicitly by a Cachex call. This means that these values come back when we access a key, and allows us to very easily check if the key should have expired before returning it to the user. If this is the case, we actually fire off a deletion of the key before returning the `nil` value to the user.

This means that at any point, if you have the Janitor disabled, you can realistically never retrieve an expired key. This provides the ability to run the Janitor less frequently, instead of having to have a tight loop in order to make sure that values can't be stale.

Of course, if you have the Janitor disabled you need to be careful of a growing cache size due to keys being added and then never being accessed again. This is fine if you have a very restrictive keyset, but for arbitrary keys this is probably not what you want.

Although the overhead of on-demand expiration is minimal, as of v0.10.0 it can be disabled using the `disable_ode` option inside `start/1` or `start_link/2`. This is useful if you have a Janitor running and don't mind keys existing a little beyond their expiration (for example if  TTL is being used purely as a means to control memory usage). The main advantage of disabling ODE is that the execution time of any given read operation is more predictable due to avoiding the case where some reads also evict the key.

## Benchmarks

There are some very trivial benchmarks available using [Benchfella](https://github.com/alco/benchfella) in the `bench/` directory. You can run the benchmarks using the following command:

```bash
# default benchmarks, no modifiers
$ mix bench

# use a state instead of a cache name
$ CACHEX_BENCH_STATE=true mix bench

# use a lock write context for all writes
$ CACHEX_BENCH_TRANSACTIONS=true mix bench

# use both a state and lock write context
$ CACHEX_BENCH_STATE=true CACHEX_BENCH_TRANSACTIONS=true mix bench
```

## Contributions

If you feel something can be improved, or have any questions about certain behaviours or pieces of implementation, please feel free to file an issue. Proposed changes should be taken to issues before any PRs to avoid wasting time on code which might not be merged upstream.

If you *do* make changes to the codebase, please make sure you test your changes thoroughly, and include any unit tests alongside new or changed behaviours. Cachex currently uses the excellent [excoveralls](https://github.com/parroty/excoveralls) to track code coverage.

```bash
$ mix test
$ mix credo
$ mix coveralls
$ mix coveralls.html && open cover/excoveralls.html
```
