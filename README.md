# Cachex
[![Coverage Status](https://img.shields.io/coveralls/whitfin/cachex.svg)](https://coveralls.io/github/whitfin/cachex) [![Unix Build Status](https://img.shields.io/travis/whitfin/cachex.svg?label=unix)](https://travis-ci.org/whitfin/cachex) [![Windows Build Status](https://img.shields.io/appveyor/ci/whitfin/cachex.svg?label=win)](https://ci.appveyor.com/project/whitfin/cachex) [![Hex.pm Version](https://img.shields.io/hexpm/v/cachex.svg)](https://hex.pm/packages/cachex) [![Documentation](https://img.shields.io/badge/docs-latest-blue.svg)](https://hexdocs.pm/cachex/)

Cachex is an extremely fast in-memory key/value store with support for many useful features:

- Time-based key expirations
- Maximum size protection
- Pre/post execution hooks
- Statistics gathering
- Multi-layered caching/key fallbacks
- Transactions and row locking
- Asynchronous write operations
- Syncing to a local filesystem
- User command invocation

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
    - [Configuration](docs/features/cache-limits.md#policies)
    - [Policies](docs/features/cache-limits.md#policies)
- [Cache Warming](docs/cache-warming)
    - [Reactive Warming](docs/cache-warming/reactive-warming.md)
        - [Overview](docs/cache-warming/reactive-warming.md#overview)
        - [Courier](docs/cache-warming/reactive-warming.md#courier)
        - [Expirations](docs/cache-warming/reactive-warming.md#expirations)
        - [Use Cases](docs/cache-warming/reactive-warming.md#use-cases)
    - [Proactive Warming](docs/cache-warming/proactive-warming.md)
        - [Overview](docs/cache-warming/proactive-warming.md#overview)
        - [Definition](docs/cache-warming/proactive-warming.md#definition)
        - [Use Cases](docs/cache-warming/proactive-warming.md#use-cases)
- [Custom Commands](docs/features/custom-commands.md)
    - [Defining Commands](docs/features/custom-commands.md#defining-commands)
    - [Invoking A Command](docs/features/custom-commands.md#invoking-a-command)
- [Disk Interaction](docs/features/disk-interaction.md)
- [Execution Hooks](docs/features/execution-hooks.md)
    - [Creating Hooks](docs/features/execution-hooks.md#creating-hooks)
    - [Provisions](docs/features/execution-hooks.md#provisions)
- [Streaming Caches](docs/features/streaming-caches.md)
    - [Basics](docs/features/streaming-caches.md#basics)
    - [Complex Streaming](docs/features/streaming-caches.md#complex-streaming)
- [TTL Implementation](docs/features/ttl-implementation.md)
    - [Janitor Processes](docs/features/ttl-implementation.md#janitor-processes)
    - [On Demand Expiration](docs/features/ttl-implementation.md#on-demand-expiration)
- [Migrations](docs/migrations)
    - [Migrating To v3.x](docs/migrations/migrating-to-v3)
    - [Migrating To v2.x](docs/migrations/migrating-to-v2)
- [Benchmarks](#benchmarks)
- [Contributions](#contributions)

## Installation

As of v0.8.0, Cachex is available on [Hex](https://hex.pm/). You can install the package via:

  1. Add cachex to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:cachex, "~> 2.1"}]
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
  [ worker(Cachex, [:my_cache, []]) ]
)
```

If you wish to start it manually (for example, in `iex`), you can just use `Cachex.start_link/2`:

```elixir
Cachex.start_link(:my_cache, [])
```

For anything else, please see the [documentation](https://github.com/whitfin/cachex/tree/master/docs).

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
