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

## Installation

As of v0.8.0, Cachex is available on [Hex](https://hex.pm/). You can install the package via:

  1. Add cachex to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:cachex, "~> 0.8.0"}]
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
