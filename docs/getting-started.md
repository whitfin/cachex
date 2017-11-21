# Getting Started

## Starting Your Cache

To start a cache you can use either `start/3` or `start_link/3`, and in general you should place it into your Supervision trees for fault tolerance. The first argument is the name of the cache and defines how you will communicate with your cache.

```elixir
Supervisor.start_link(
  [
    worker(Cachex, [ :my_cache, [], [] ])
  ]
)
```

The second and third arguments are both optional and represent cache and server options respectively. Cache options can be set on a cache at startup and cannot be modified. They're defined on a per-cache basis and control the features available to the cache. This table contains a summary of most of the available options, but please look at the module documentation either in GitHub or on Hexdocs for full documentation on what each one can configure.

|      Options     |       Values       |                               Description                               |
|:----------------:|:------------------:|:-----------------------------------------------------------------------:|
|     commands     |  list of commands  |     A list of custom commands to attach to the cache for invocation     |
|    default_ttl   |     milliseconds   | A default expiration time for a key when being placed inside the cache. |
|     fallback     |  Function or List  |   A function accepting a key which is used for multi-layered caching.   |
|       hooks      |    list of Hooks   |    A list of execution hooks (see below) to listen on cache actions.    |
|       limit      |  a Limit constuct  |     An integer or Limit struct to define the bounds of this cache.      |
|        ode       |  `true` or `false` |  Whether or not to enable on-demand expirations when reading back keys. |
|       stats      |  `true` or `false` |            Whether to track statistics for this cache or not.           |
|   transactions   |  `true` or `false` |             Whether to turn on transactions at cache start.             |
|   ttl_interval   |     milliseconds   |                The frequency the Janitor process runs at.               |

## Main Interface

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
