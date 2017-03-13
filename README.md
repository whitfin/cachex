# Cachex
[![Coverage Status](https://img.shields.io/coveralls/zackehh/cachex.svg)](https://coveralls.io/github/zackehh/cachex) [![Unix Build Status](https://img.shields.io/travis/zackehh/cachex.svg?label=unix)](https://travis-ci.org/zackehh/cachex) [![Windows Build Status](https://img.shields.io/appveyor/ci/zackehh/cachex.svg?label=win)](https://ci.appveyor.com/project/zackehh/cachex) [![Hex.pm Version](https://img.shields.io/hexpm/v/cachex.svg)](https://hex.pm/packages/cachex) [![Documentation](https://img.shields.io/badge/docs-latest-blue.svg)](https://hexdocs.pm/cachex/)

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
- [Getting Started](docs/Getting Started.md)
    - [Starting Your Cache](docs/Getting Started.md#starting-your-cache)
    - [Main Interface](docs/Getting Started.md#main-interface)
- [Action Blocks](docs/Action Blocks.md)
    - [Execution Blocks](docs/Action Blocks.md#execution-blocks)
    - [Transaction Blocks](docs/Action Blocks.md#transaction-blocks)
- [Cache Limits](docs/Cache Limits.md)
    - [Configuration](docs/Cache Limits.md#policies)
    - [Policies](docs/Cache Limits.md#policies)
- [Custom Commands](docs/Custom Commands.md)
    - [Defining Commands](docs/Custom Commands.md#defining-commands)
    - [Invoking A Command](docs/Custom Commands.md#invoking-a-command)
- [Disk Interaction](docs/Disk Interaction.md)
- [Execution Hooks](docs/Execution Hooks.md)
    - [Creating Hooks](docs/Execution Hooks.md#creating-hooks)
    - [Provisions](docs/Execution Hooks.md#provisions)
- [Fallback Caching](docs/Fallback Caching.md)
    - [Common Use Cases](docs/Fallback Caching.md#common-use-cases)
    - [Expirations](docs/Fallback Caching.md#expirations)
    - [Handling Errors](docs/Fallback Caching.md#handling-errors)
- [TTL Implementation](docs/TTL Implementation.md)
    - [Janitor Processes](docs/TTL Implementation.md#janitor-processes)
    - [On Demand Expiration](docs/TTL Implementation.md#on-demand-expiration)
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
  [
    worker(Cachex, [:my_cache, []])
  ]
)
```

If you wish to start it manually (for example, in `iex`), you can just use `Cachex.start_link/2`:

```elixir
Cachex.start_link(:my_cache, [])
```

For anything else, please see the [documentation](https://github.com/zackehh/cachex/tree/master/docs).

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
