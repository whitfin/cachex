# Cachex
[![Build Status](https://img.shields.io/travis/zackehh/cachex.svg)](https://travis-ci.org/zackehh/cachex) [![Coverage Status](https://img.shields.io/coveralls/zackehh/cachex.svg)](https://coveralls.io/github/zackehh/cachex) [![Hex.pm Version](https://img.shields.io/hexpm/v/cachex.svg)](https://hex.pm/packages/cachex) [![Documentation](https://img.shields.io/badge/docs-latest-yellowgreen.svg)](https://hexdocs.pm/cachex/)

Cachex is an extremely fast in-memory key/value store with support for many useful features:

- Time-based key expirations
- Pre/post execution hooks
- Statistics gathering
- Multi-layered caching/key fallbacks
- Distribution to remote nodes
- Transactions and row locking
- Asynchronous write operations

All of these features are optional and are off by default so you can pick and choose those you wish to enable.

## Table of Contents

- [Installation](#installation)
- [Usage](#usage)
- [Cache Options](#cache-options)
- [Multi-Layered Caches](#multi-layered-caches)
- [Execution Hooks](#execution-hooks)
    - [Definition](#definition)
    - [Registration](#registration)
    - [Performance](#performance)
- [TTL Implementation](#ttl-implementation)
    - [On Demand Expiration](#on-demand-expiration)
    - [Janitors](#janitors)
    - [TTL Distribution](#ttl-distribution)
- [Interface](#interface)
- [Contributions](#contributions)

## Installation

As of v0.8.0, Cachex is available on [Hex](https://hex.pm/). You can install the package via:

  1. Add cachex to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:cachex, "~> 0.8.2"}]
    end
    ```

  2. Ensure cachex is started before your application:

    ```elixir
    def application do
      [applications: [:cachex]]
    end
    ```

## Usage

The typical use of Cachex is to set up using a Supervisor, so that it can be handled automatically:

```elixir
Supervisor.start_link(
  [
    worker(Cachex, [[ name: :my_cache ], []])
  ]
)
```

If you wish to start it manually (for example, in `iex`), you can just use `Cachex.start_link/2`:

```elixir
Cachex.start_link([ name: :my_cache ], [])
```

Although this is possible and is functionally the same internally, it's probably better to set up the supervision tree for fault-tolerance. As shown in the above examples, the only **required** option is the `name` option. This is the name of your cache and is how you will typically refer to the cache in the `Cachex` module.

## Cache Options

Caches can accept a list of options during initialization, which determine various behaviour inside your cache. These options are defined on a per-cache basis and cannot be changed after being set.

|      Options     |       Values       |                               Description                               |
|:----------------:|:------------------:|:-----------------------------------------------------------------------:|
|     ets_opts     |   list of options  |               A list of options to give to the ETS table.               |
| default_fallback |       function     |   A function accepting a key which is used for multi-layered caching.   |
|    default_ttl   |     milliseconds   | A default expiration time for a key when being placed inside the cache. |
|   fallback_args  |  list of arguments |  A list of arguments to pass alongside the key to a fallback function.  |
|       hooks      |    list of Hooks   |    A list of execution hooks (see below) to listen on cache actions.    |
|       nodes      |    list of nodes   |       A list of remote nodes to connect to and replicate against.       |
|   record_stats   |  `true` or `false` |            Whether to track statistics for this cache or not.           |
|      remote      |  `true` or `false` |              Whether to use replication with writes or not.             |
|   transactional  |  `true` or `false` |       Whether to enclose all cache actions in transactions or not.      |
|   ttl_interval   |     milliseconds   |          The frequency the Janitor process runs at (see below).         |

For more information and examples, please see the official documentation on [Hex](https://hexdocs.pm/cachex/).

## Multi-Layered Caches

A very common use case (and one of the reasons I built Cachex) is the desire to have Multi-Layered Caches. Multi-layering is the idea of a backing cache (i.e. something remote) which populates your local caches on misses. A typical pattern is using [Redis](http://redis.io) as a remote data store and replicating it locally in-memory for faster access.

Let's look at an example; assume you need to read information from a database to service a public API. The issue is that the query is expensive and so you want to cache it locally for 5 minutes to avoid overloading your database. To do this with Cachex, you would simply specify a TTL of 5 minutes on your cache, and use a fallback to read from your database.

```elixir
# initialize our database client
{ :ok, db } = initialize_database_client()

# initialize the cache instance
{ :ok, pid } = Cachex.start_link([ name: :info_cache, default_ttl: :timer.minutes(5), fallback_args: [db] ])

# request our information on our "packages" API
{ :ok, information } = Cachex.get(:info_cache, "/api/v1/packages", fallback: fn(key, db) ->
  Database.query_all_packages(db)
end)
```

That's all there is to it. The above is a multi-layered cache which only hits the database **at most** every 5 minutes, and hits local memory in the meantime (retrieving the exact same data as was returned from your database). This allows you to easily lower the pressure on your backing systems - the value returned by your fallback is set in the cache against the key.

Note that the above use defines the fallback implementation inside the `Cachex.get/3` command itself, but for a more general fallback you can assign it in the Cachex options. This is perhaps more fitting for something like Redis, where you're simply replicating the remote information locally:

## Execution Hooks

Cachex provides an easy way to plug into cache actions, by way of the hook system. This system allows the user to specify pre/post execution hooks which are notified when actions are taken.

These hooks accept messages in the form of tuples which represent the action being taken. These tuples basically represent `[:action|action_args]`, where `:action` represents the name of the function being executed inside Cachex, and `action_args` represent the arguments provided to the function.

It's pretty straightforward, but in the interest of completeness, here is a quick example of how a Cachex command translates to the notification format:

```elixir
Cachex.get(:my_cache, "key") == { :get, :my_cache, "key" }
```

Cachex uses the typical `GenServer` pattern (it's actually a `GenEvent` implementation under the hood), and as such you get most of the typical interfaces. There are a couple of differences, but they're detailed below.

#### Definition

Hooks are quite simply a small abstraction above the existing `GenEvent` which ships with Elixir. Cachex tweaks a couple of minor things related to synchronous execution and argument format, but nothing too special. Below is an example of a very basic hook implementation:


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
  This is the actual handler of your hook, receiving a message and the state. This
  behaves in the same way as `GenEvent.handle_event/2` in that you can modify the
  state and return it at the end of your function.

  Messages take the form `{ :action, args... }`, so you can quite easily pattern
  match and take different action based on different events (or ignore certain
  events entirely).
  """
  def handle_notify(msg, state) do
    IO.puts("Message: #{msg}")
    { :ok, msg }
  end

  @doc """
  This is functionally the same as the above `handle_notify/2` definition except
  that it receives the results of the action taken. This will only ever be called
  if you set `results` to `true` in your hook registration.

  Message formats are as above, and results are of the same format as if they had
  been returned in the main worker thread.
  """
  def handle_notify(msg, results, state) do
    IO.puts("Message: #{msg}")
    IO.puts("Results: #{results}")
    { :ok, msg }
  end

  @doc """
  Provides a way to retrieve the last action taken inside the cache.
  """
  def handle_call(:last_action, state) do
    { :ok, state, state }
  end

end
```

You can override any of the typical callback functions *except* for the `handle_event/2` callback inside `GenEvent` which is used by Cachex. This is because Cachex hijacks `handle_event/2` and adds some bindings based around synchronous execution, so for safety it's easier to keep this away from the user. Cachex exposes the `handle_notify/2` and `handle_notify/3` callbacks in order to replace this behaviour by operating in the same way as `handle_event/2`.

#### Registration

To register hooks with Cachex, they must be passed in when setting up a cache in the call to `Cachex.start_link/2` (or in your Supervisor). This looks something like the following:

```elixir
defmodule MyModule do

  @on_load :init_cache

  def init_cache do
    my_hooks = [%Cachex.Hook{
      module: MyProject.MyHook,
      server_args: [ name: :my_project_hook ]
    }]
    { :ok, pid } = Cachex.start_link([ name: :my_cache, hooks: my_hooks ])
    :ok
  end

end
```

A hook is an instance of the `%Cachex.Hook{}` struct. These structs store various options associated with hooks alongside a listener module and look similar to that shown below (the values used below are the defaults):

```elixir
%Cachex.Hook{
  args: [],
  async: true,
  max_timeout: 5,
  module: nil,
  results: false,
  server_args: [],
  type: :pre
}
```

These fields translate to the following:

|   Option  |       Values       |                          Description                           |
|:---------:|:------------------:|:--------------------------------------------------------------:|
|    args   |        any         |      Arguments to pass to the initialization of your hook.     |
|   async   | `true` or `false`  |     Whether or not this hook should execute asynchronously.    |
|max_timeout| no. of milliseconds| A maximum time to wait for your synchronous hook to complete.  |
|   module  | a module definition| A module containing your which implements the Hook interface.  |
|  results  | `true` or `false`  |     Whether the results should be included in notifications.   |
|server_args|        any         |           Arguments to pass to the GenEvent server.            |
|   type    | `:pre` or `:post`  |   Whether this hook should execute before or after the action. |

**Notes**

- `max_timeout` has no effect if the hook is not being executed in a synchronous form.
- `module` is the only required argument, as there's no logical default to set if not provided.
- `results` has no effect on `:pre` hooks (as naturally results can only be forwarded after the action has taken place. Do not forget that this option has an effect on which callback is called (either `/2` or `/3`).

#### Performance

Due to the way hooks are implemented and notified internally, there is only a very minimal overhead to defining a hook (usually around a microsecond per definition). Naturally if you define a synchronous hook then the performance depends entirely on the actions taken inside the hook (up until the timeout).

Hooks are always notified sequentially as spawning another process for each has far too much overhead, and so you should keep this in mind when using synchronous hooks as 3 hooks which all take a second to execute will cause the Cachex action to take at least 3 seconds before completing.

## TTL Implementation

Cachex implements a few different ways of working with key expiration, namely the background TTL loop and on-demand key expiration. Separately these two techniques aren't enough to provide an efficient system as your keyspace would either grow too large due to keys not being accessed and purged on access, or you would be able to retrieve values which should have expired. Cachex opts for a combination of both in order to ensure consistency whilst also reducing pressure on things like table scans.

#### On Demand Expiration

Keys have an internal touch time and TTL associated with them, and these values do not change unless triggered explicitly by a Cachex call. This means that these values come back when we access a key, and allows us to very easily check if the key should have expired before returning it to the user. If this is the case, we actually fire off a deletion of the key before returning the `nil` value to the user.

This means that at any point, if you have the TTL worker disabled, you can realistically never retrieve an expired key. This provides the ability to run the TTL worker less frequently, instead of having to have a tight loop in order to make sure that values can't be stale.

Of course, if you have the TTL worker disabled you need to be careful of a growing cache size due to keys being added and then never being accessed again. This is fine if you have a very restrictive keyset, but for
arbitrary keys this is probably not what you want.

This type of expiration is always enabled and cannot be disabled. Due to the extremely minimal overhead, it doesn't really make sense to make this optional.

#### Janitors

Cachex also enables a background process (nicknamed the `Janitor`) which will purge the internal table every so often. The Janitor operates using **full-table scans** and so you should be relatively careful about how often you run it. The interval that this process runs can be controlled, and Janitors exist on a per-cache basis (i.e. each cache has its own Janitor).

The Janitor is pretty well optimized; it can check and purge 500,000 expired keys in around a second (where the removal takes the most time, the check is very fast). As such, you're probably fine running it however often you wish but please keep in mind that running less frequently means you're not releasing the memory of expired keys. A typical use case is probably to run the Janitor every few seconds, and this is used as a default in a couple of places.

There are several rules to be aware of when setting up the interval:

- If you have `default_ttl` set in the cache options, and you have not set `ttl_interval`, the Janitor will default to running every 3 seconds. This is to avoid people forgetting to set it or simply being unaware that it's not running by default.
- If you set `ttl_interval` to either `false` or `-1`, it is disabled entirely - even if you have a `default_ttl` set. This means you will be solely reliant on the on-demand expiration policy.
- If you set `ttl_interval` to `true`, it behaves the same way as if you had set a `default_ttl`; it will set the Janitor to run every 3 seconds.
- If you set `ttl_interval` to any numeric value above `0`, it will run on this schedule (this value is in milliseconds).

It should be noted that this is a rolling value which is set **on completion** of a run. This means that if you schedule the Janitor to run every 1ms, it will be 1ms after a successful run, rather than starting every 1ms. This may become configurable in the future if there's demand for it, but for now rolling seems to make the most sense.

#### TTL Distribution

The combination of Janitors and ODE means that distributed TTL becomes way easier because you *don't* have to replicate the purges to the other servers. The Janitors only ever run against the local machine, because Janitors naturally live on all machines.

This has the benefit of all machines cleaning up their local environment (assuming they all use the same schedules, which will always be the case in practice). Even though these schedules can get out of sync, if you access a key which should have expired, it'll then be removed due to ODE. This means that it's not possible to retrieve a key which has expired on one node and not another. This is a small example of eventual consistency and in theory (and practice) should be safe enough.

During tests, the replication of a TTL purge during a transaction took an *extremely* long time. The same purge mentioned above (of 500,000 keys) took at least 6 seconds when done in a potentially unsafe way. When carried out in a totally transactional way it took upwards of 20 seconds. Clearly, this is definitely not good enough for potentially high throughput systems, and as such opting for each node cleaning only itself up was decided on.

## Interface

The Cachex interface should/will be maintained such that it follows this pattern:

```elixir
Cachex.action(:cache_ref, _required_args, _options \\ [])
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
{:error, "Invalid cache name provided, got: :missing_cache"}
iex(4)> Cachex.get!(:missing_cache, "key")
** (Cachex.ExecutionError) Invalid cache name provided, got: :missing_cache
    (cachex) lib/cachex/macros/boilerplate.ex:77: Cachex.Macros.Boilerplate.raise_result/1
```

I'd typically recommend checking the values and using the safe version which gives you a tuple, but sometimes it's easier to use the unsafe version (for example in unit tests).

## Contributions

If you feel something can be improved, or have any questions about certain behaviours or pieces of implementation, please feel free to file an issue. Proposed changes should be taken to issues before any PRs to avoid wasting time on code which might not be merged upstream.

If you *do* make changes to the codebase, please make sure you test your changes thoroughly, and include any unit tests alongside new or changed behaviours. Cachex currently uses the excellent [excoveralls](https://github.com/parroty/excoveralls) to track code coverage.

```elixir
$ mix test --trace
$ mix coveralls
$ mix coveralls.html && open cover/excoveralls.html
```
