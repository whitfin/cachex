# Cachex
[![Build Status](https://img.shields.io/github/actions/workflow/status/whitfin/cachex/ci.yml?branch=main)](https://github.com/whitfin/cachex/actions) [![Coverage Status](https://img.shields.io/coveralls/whitfin/cachex.svg)](https://coveralls.io/github/whitfin/cachex) [![Hex.pm Version](https://img.shields.io/hexpm/v/cachex.svg)](https://hex.pm/packages/cachex) [![Documentation](https://img.shields.io/badge/docs-latest-blue.svg)](https://hexdocs.pm/cachex/)

Cachex is an extremely fast in-memory key/value store with support for many useful features:

- Time-based key expirations
- Maximum size protection
- Pre/post execution hooks
- Proactive/reactive cache warming
- Transactions and row locking
- Asynchronous write operations
- Distribution across app nodes
- Syncing to a local filesystem
- Idomatic cache streaming
- Batched write operations
- User command invocation
- Statistics gathering

All of these features are optional and are off by default so you can pick and choose those you wish to enable.

## Table of Contents

- [Installation](#installation)
- [Getting Started](docs/getting-started.md)
    - [Starting Your Cache](docs/getting-started.md#starting-your-cache)
    - [Main Interface](docs/getting-started.md#main-interface)
- [Action Blocks](docs/features/action-blocks.md)
    - [Execution Blocks](docs/features/action-blocks.md#execution-blocks)
    - [Transaction Blocks](docs/features/action-blocks.md#transaction-blocks)
- [Cache Limits](docs/features/cache-limits.md)
    - [Configuration](docs/features/cache-limits.md#configuration)
    - [Policies](docs/features/cache-limits.md#policies)
- [Cache Warming](docs/features/cache-warming)
    - [Reactive Warming](docs/features/cache-warming/reactive-warming.md)
        - [Overview](docs/features/cache-warming/reactive-warming.md#overview)
        - [Courier](docs/features/cache-warming/reactive-warming.md#courier)
        - [Expirations](docs/features/cache-warming/reactive-warming.md#expirations)
        - [Use Cases](docs/features/cache-warming/reactive-warming.md#use-cases)
    - [Proactive Warming](docs/features/cache-warming/proactive-warming.md)
        - [Overview](docs/features/cache-warming/proactive-warming.md#overview)
        - [Definition](docs/features/cache-warming/proactive-warming.md#definition)
        - [Use Cases](docs/features/cache-warming/proactive-warming.md#use-cases)
- [Custom Commands](docs/features/custom-commands.md)
    - [Defining Commands](docs/features/custom-commands.md#defining-commands)
    - [Invoking A Command](docs/features/custom-commands.md#invoking-a-command)
- [Disk Interaction](docs/features/disk-interaction.md)
- [Distributed Caches](docs/features/distributed-caches.md)
    - [Overview](docs/features/distributed-caches.md#overview)
    - [Local Actions](docs/features/distributed-caches.md#local-actions)
    - [Disabled Actions](docs/features/distributed-caches.md#disabled-actions)
- [Execution Hooks](docs/features/execution-hooks.md)
    - [Creating Hooks](docs/features/execution-hooks.md#creating-hooks)
    - [Provisions](docs/features/execution-hooks.md#provisions)
- [Streaming Caches](docs/features/streaming-caches.md)
    - [Complex Streaming](docs/features/streaming-caches.md#complex-streaming)
- [TTL Implementation](docs/features/ttl-implementation.md)
    - [Janitor Processes](docs/features/ttl-implementation.md#janitor-processes)
    - [Lazy Expiration](docs/features/ttl-implementation.md#lazy-expiration)
- [Migrations](docs/migrations)
    - [Migrating To v3.x](docs/migrations/migrating-to-v3.md)
    - [Migrating To v2.x](docs/migrations/migrating-to-v2.md)
- [Benchmarks](#benchmarks)
- [Contributions](#contributions)

## Installation

As of v0.8, Cachex is available on [Hex](https://hex.pm/). You can install the package via:

```elixir
def deps do
  [{:cachex, "~> 3.6"}]
end
```

## Usage

In the most typical use of Cachex, you only need to add your cache as a child of your application. If you created your project via `Mix` (passing the `--sup` flag) this is handled in `lib/my_app/application.ex`. This file will already contain an empty list of children to add to your application - simply add entries for your cache to this list:

```elixir
children = [
  {Cachex, name: :my_cache_name}
]
```

If you wish to start a cache manually (for example, in `iex`), you can just use `Cachex.start_link/2`:

```elixir
Cachex.start_link(name: :my_cache)
```

For anything else, please see the [documentation](https://github.com/whitfin/cachex/tree/master/docs).

## Benchmarks

There are some very trivial benchmarks available using [Benchee](https://github.com/PragTob/benchee) in the `benchmarks/` directory. You can run the benchmarks using the following command:

```bash
# default benchmarks, no modifiers
$ mix bench

# enable underlying table compression
$ CACHEX_BENCH_COMPRESS=true mix bench

# use a state instead of a cache name
$ CACHEX_BENCH_STATE=true mix bench

# use a lock write context for all writes
$ CACHEX_BENCH_TRANSACTIONS=true mix bench
```

Any combination of these environment variables is also possible, to allow you to test and benchmark your specific workflows.

## Contributions

If you feel something can be improved, or have any questions about certain behaviours or pieces of implementation, please feel free to file an issue. Proposed changes should be taken to issues before any PRs to avoid wasting time on code which might not be merged upstream.

If you *do* make changes to the codebase, please make sure you test your changes thoroughly, and include any unit tests alongside new or changed behaviours. Cachex currently uses the excellent [excoveralls](https://github.com/parroty/excoveralls) to track code coverage.

```bash
$ mix test # --exclude=distributed to skip slower tests
$ mix credo
$ mix coveralls
$ mix coveralls.html && open cover/excoveralls.html
```
