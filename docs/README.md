# Cachex Documentation

## Table of Contents

- [Installation](../README.md#installation)
- [Getting Started](#getting-started)
    - [Starting Your Cache](#starting-your-cache)
    - [Main Interface](#main-interface)
- [Action Blocks](features/action-blocks.md)
    - [Execution Blocks](features/action-blocks.md#execution-blocks)
    - [Transaction Blocks](features/action-blocks.md#transaction-blocks)
- [Cache Limits](features/cache-limits.md)
    - [Configuration](features/cache-limits.md#configuration)
    - [Policies](features/cache-limits.md#policies)
- [Cache Warming](features/cache-warming)
    - [Reactive Warming](features/cache-warming/reactive-warming.md)
        - [Overview](features/cache-warming/reactive-warming.md#overview)
        - [Courier](features/cache-warming/reactive-warming.md#courier)
        - [Expirations](features/cache-warming/reactive-warming.md#expirations)
        - [Use Cases](features/cache-warming/reactive-warming.md#use-cases)
    - [Proactive Warming](features/cache-warming/proactive-warming.md)
        - [Overview](features/cache-warming/proactive-warming.md#overview)
        - [Definition](features/cache-warming/proactive-warming.md#definition)
        - [Use Cases](features/cache-warming/proactive-warming.md#use-cases)
- [Custom Commands](features/custom-commands.md)
    - [Defining Commands](features/custom-commands.md#defining-commands)
    - [Invoking A Command](features/custom-commands.md#invoking-a-command)
- [Disk Interaction](features/disk-interaction.md)
- [Distributed Caches](features/distributed-caches.md)
    - [Overview](features/distributed-caches.md#overview)
    - [Local Actions](features/distributed-caches.md#local-actions)
    - [Disabled Actions](features/distributed-caches.md#disabled-actions)
- [Execution Hooks](features/execution-hooks.md)
    - [Creating Hooks](features/execution-hooks.md#creating-hooks)
    - [Provisions](features/execution-hooks.md#provisions)
- [Streaming Caches](features/streaming-caches.md)
    - [Complex Streaming](features/streaming-caches.md#complex-streaming)
- [TTL Implementation](features/ttl-implementation.md)
    - [Janitor Processes](features/ttl-implementation.md#janitor-processes)
    - [Lazy Expiration](features/ttl-implementation.md#lazy-expiration)
- [Migrations](migrations)
    - [Migrating To v3.x](migrations/migrating-to-v3.md)
    - [Migrating To v2.x](migrations/migrating-to-v2.md)
- [Benchmarks](../README.md#benchmarks)
- [Contributions](../README.md#contributions)

## Getting Started

### Starting Your Cache

To start a cache you can use either `start/2` or `start_link/2`, and in general you should place it into your Supervision trees for fault tolerance. The first argument is the name of the cache and defines how you will communicate with your cache.

```elixir
Supervisor.start_link(
  [{Cachex, name: :my_cache}],
  [strategy: :one_for_one]
)
```

The second and third arguments are both optional and represent cache and server options respectively. Cache options can be set on a cache at startup and cannot be modified. They're defined on a per-cache basis and control the features available to the cache. This table contains a summary of most of the available options, but please look at the module documentation either in GitHub or on Hexdocs for full documentation on what each one can configure.

|      Options     |          Values          |                             Description                            |
|:----------------:|:------------------------:|:------------------------------------------------------------------:|
|     commands     |      map or keyword      |       A collection of custom commands to attach to the cache.      |
|    expiration    |      `expiration()`      |      An expiration options record imported from Cachex.Spec.       |
|     fallback     | function or `fallback()` |            A fallback record imported from Cachex.Spec.            |
|       hooks      |     list of `hook()`     |        A list of execution hooks to listen on cache actions.       |
|       limit      |    a `limit()` record    |    An integer or Limit struct to define the bounds of this cache.  |
|       stats      |          boolean         |         Whether to track statistics for this cache or not.         |
|   transactions   |          boolean         |           Whether to turn on transactions at cache start.          |
|      warmers     |    list of `warmer()`    |           A list of cache warmers to enable on the cache.          |

### Main Interface

The Cachex interface follows a specific standard to make it easier to predict and more user friendly. All calls should follow the pattern of having the cache argument first, followed by any required arguments and ending with an optional list of options (even if no options are currently used). All calls should result in a value in the format of `{ status, result }` where `status` is usually `:ok` or `:error` (however this differs depending on the call). The `result` can basically be anything, as there are a number of custom controlled return values available inside Cachex.

In the interest of convenience all Cachex actions have an automatically generated "unsafe" equivalent (appended with `!`) which unwraps these result Tuples. This unwrapping assumes that `:error` status means that the result should be raised, and that any other status should just return the result itself.

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

In production code I would typically recommend the safer versions to be explicit but the `!` version exists for both convenience and unit test code to make assertions easier.
