# Getting Started

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

## Setting Up

To get started, please add Cachex to your `mix.exs` list of dependencies and then pull it using `mix deps.get`:

```elixir
def deps do
  [{:cachex, "~> 3.6"}]
end
```

Depending on what you're trying to do, there are a couple of different ways you might want to go about starting a cache.

If you're testing out Cachex inside `iex`, you can call `Cachex.start_link/2` manually:

```elixir
Cachex.start_link(:my_cache)     # with default options
Cachex.start_link(:my_cache, []) # with custom options
```

In other cases, you might want to start a cache within an existing supervision tree. If you created your project via `mix` with the `--sup` flag, this should be available to you inside `lib/my_app/application.ex`:

```elixir
children = [
  {Cachex, [:my_cache]},     # with default options
  {Cachex, [:my_cache, []]}  # with custom options
]
```

Both of these approaches work the same way; your options are parsed and your cache is started as a child under the appropriate parent process. The latter is recommended for production applications, as it will ensure your cache is managed correctly inside your application.

## Basic Operations

Working with a cache is pretty straightforward, and basically everything is provided by the core `Cachex` module. You can make calls to a cache using the name you registered it under at startup time.

Let's take a quick look at some basic calls you can make to a cache in a quick `iex` session:

```elixir
# create a default cache in our shell session
{:ok, _pid} = Cachex.start_link(:my_cache)

# place a "my_value" string against the key "my_key"
{:ok, true} = Cachex.put(:my_cache, "my_key", "my_value")

# verify that the key exists under the key name
{:ok, true} = Cachex.exists?(:my_cache, "my_key")

# verify that "my_value" is returned when we retrieve
{:ok, "my_value"} = Cachex.get(:my_cache, "my_key")

# remove the "my_key" key from the cache
{:ok, true} = Cachex.del(:my_cache, "my_key")

# verify that the key no longer exists
{:ok, false} = Cachex.exists?(:my_cache, "my_key")

# verify that "my_value" is no longer returned
{:ok, nil} = Cachex.get(:my_cache, "my_key")
```

It's worth noting here that the actions supported by the Cachex API have an automatically generated "unsafe" equivalent (i.e. appended with `!`). These options will unpack the returned tuple, and return values directly:

```elixir
# calling by default will return a tuple
{:ok, nil} = Cachex.get(:my_cache, "key")

# calling with `!` unpacks the tuple
nil = Cachex.get!(:my_cache, "key")

# causing an error will return an error tuple value
{:error, :no_cache} =  Cachex.get(:missing_cache, "key")

# but calling with `!` raises the error
Cachex.get!(:missing_cache, "key")
** (Cachex.ExecutionError) Specified cache not running
    (cachex) lib/cachex.ex:249: Cachex.get!/3
```

The `!` version of functions exists for convenience, in particular to make chaining and assertions easier in unit testing. For production use cases it's recommended to avoid `!` wrappers, and instead explicitly handle the different response types.

## Advanced Operations

Beyond the typical get/set semantics of a cache, Cachex offers many additional features to help with typical use cases and access patterns a developer may meeting during their day-to-day.

While the list is too long to properly cover everything in detail here, let's take a look at some of the most common cache actions:

```elixir
# create a default cache in our shell session
{:ok, _pid} = Cachex.start_link(:my_cache)

# place some values in a single batch call
{:ok, true} = Cachex.put_many(:my_cache, [
    {"key1", 1},
    {"key2", 2},
    {"key3", 3}
])

# now let's do an atomic update operation against the key in the cache
{:commit, 2} = Cachex.get_and_update(:my_cache, "key1", fn value ->
    value + 1
end)

# we can also do this via `Cachex.incr/2`
{:ok, 2} = Cachex.incr(:my_cache, "key2")

# and of course the inverse via `Cachex.decr/2`
{:ok, 0} = Cachex.decr(:my_cache, "key3")

# we can also lazily compute keys if they're missing from the cache
{:commit, "nazrat"} = Cachex.fetch(:my_cache, "tarzan", fn key ->
  {:commit, String.reverse(key)}
end)

# we can also write keys with an time expiration (in milliseconds)
{:ok, true} = Cachex.put(:my_cache, "secret_mission", "...", expire: 1)

# and if we pull it back after expiration, it's not there!
{:ok, nil} = Cachex.get(:my_cache, "secret_mission")
```

These are just some of the conveniences made available by Cachex's API, but there's a still a bunch of other fun stuff in the `Cachex` API, covering a broad range of patterns and use cases.

For further information or examples on supported features and options, please see the Cachex [documentation](https://hexdocs.pm/cachex) where there are several guides on specific features and workflows.

All of the hosted documentation is also available in raw form in the [repository](https://github.com/whitfin/cachex/tree/main/docs).
