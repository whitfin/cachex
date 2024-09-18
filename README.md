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
- Idiomatic cache streaming
- Batched write operations
- User command invocation
- Statistics gathering

All of these features are optional and are off by default so you can pick and choose those you wish to enable.

## Installation

As of v0.8, Cachex is available on [Hex](https://hex.pm/). You can install the package via:

```elixir
def deps do
  [{:cachex, "~> 3.6"}]
end
```

## Usage

In general use of Cachex, you'll likely only need to add your cache as a child of your application. If you created your project via `Mix`, this is usually handled in `lib/my_app/application.ex`:

```elixir
children = [
  {Cachex, name: :my_cache_name}
]
```

If you wish to start a cache manually (for example, in `iex`), you can use `Cachex.start_link/2`:

```elixir
Cachex.start_link(name: :my_cache)
```

Once your cache has started you can call any of the main Cachex API using the name of your cache. All Cachex actions have an automatically generated "unsafe" equivalent (appended with `!`):

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

Generally you should use the non-`!` versions to be more explicit in your code, but the `!` version exists for convenience and to make assertions easier in unit testing.

## Options

Caches also accept several options at startup to toggle various behaviour. These options are defined on a per-cache basis and can be used to control the features available to the cache:

|      Options     |          Values          |                             Description                            |
|:----------------:|:------------------------:|:------------------------------------------------------------------:|
|     commands     |      map or keyword      |       A collection of custom commands to attach to the cache.      |
|    expiration    |      `expiration()`      |      An expiration options record imported from `Cachex.Spec`.     |
|       hooks      |     list of `hook()`     |        A list of execution hooks to listen on cache actions.       |
|       limit      |    a `limit()` record    |    An integer or Limit struct to define the bounds of this cache.  |
|       stats      |          boolean         |         Whether to track statistics for this cache or not.         |
|   transactions   |          boolean         |           Whether to turn on transactions at cache start.          |
|      warmers     |    list of `warmer()`    |           A list of cache warmers to enable on the cache.


For further information or examples on these features and options, please see the [documentation](https://hexdocs.pm/cachex).

## Benchmarks

There are some very trivial benchmarks available using [Benchee](https://github.com/PragTob/benchee) in the `benchmarks/` directory. You can run the benchmarks using the following command:

```bash
# default benchmarks
$ mix bench

# enable benchmarks for compressed tests
$ CACHEX_BENCH_COMPRESS=true mix bench

# enable benchmarks for transactional tests
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
