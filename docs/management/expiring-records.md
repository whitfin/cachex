# Expiring Records

Cachex implements several different ways to work with key expiration, with each operating with slightly different behaviour. The two main techniques in use currently are background expiration and lazy expiration. Although there are cases where you may wish to only use one of these approaches, you'll generally want a combination of both to ensure correctness of your cache. By default Cachex will combine both approaches to provide more intuitive behaviour for the developer.

## Janitor Services

The Cachex Janitor is a background process used to purge the internal cache tables periodically. The Janitor operates using a full table sweep of records to ensure consistency and correctness. As such, a Janitor sweep will run somewhat less frequently - by default only once every few seconds. This frequency can be controlled by the developer, and can be controlled on a per-cache basis.

In the current version of Cachex, the Janitor is pretty well optimized as most of the work happens in the ETS layer. As a rough benchmark, it can check and purge 500,000 expired records in around a second (where the removal is a majority of the work). Keep in mind that the frequency of the Janitor execution has an impact on the memory being held by the expired keyset in your cache. For most use cases the default frequency should be just fine. If you need to, you can customize the frequency on which the Janitor runs:

```elixir
import Cachex.Spec

Cachex.start(:my_cache, [
    expiration: expiration(interval: :timer.seconds(3))
])
```

The Janitor is the only feature which is enabled by default, as it was misleading for users when it was not running by default. To disable the Janitor completely, you can set the `:interval` option to `nil`. In this case you will either be fully reliant on lazy expirations, or have to implement your own expiration handling.

Please note that this is rolling interval that is set to trigger after completion of a run, meaning that if you schedule a Janitor every 5s it will be 5s after a successful run rather than 5s after the last trigger fired to start a run.

## Lazily Expiring Keys

A cache record contains an internal modification time, as well as an associated expiration time. These values do not change unless explicitly modified by a cache call. This means that we have access to these values when fetching a key, which allows us to quickly check expirations on retrieval.

If a key is retrieved after the expiration has passed, the key will be removed at that time and return `nil` to the caller just as if the key did not exist in the cache. This provides guarantees of consistency even if the Janitor hasn't run recently; you can still never accidentally fetch an expired key. In turn this allows us to run the Janitor a little less frequently as we don't have to be scared of stale values.

There is a very minimal overhead to this lazy checking, and there are cases where you don't need to be as accurate. For these reasons you can easily disable this behaviour by seting the `:lazy` option to false at cache startup:

```elixir
import Cachex.Spec

Cachex.start(:my_cache, [
    expiration: expiration(lazy: false)
])
```

Another advantage of disabling this checking is that the execution times of your read operations become more uniform; there's no longer a case where a deletion may make a read take a little longer. That being said, the overhead is so small that it's recommended to leave this enabled unless you absolutely know you don't need it.

Naturally this technique cannot stand alone as it only evicts on key retrieval; if you never touch a record again, it would never be expired and thus your cache would just keep growing. For this reason the Janitor is enabled by default when an expiration is set to protect the user from memory errors in their application. It should also be noted that this approach only applies to single key retrieval; it does not activate on batch reads (such as `Cachex.stream/3`).

## Providing Key Expirations

There are a number of ways to provide expirations for entries inside a cache:

* Setting a default expiration for a cahe via `Cachex.start_link/2`
* Setting an expiration manually via `Cachex.expire/4` or `Cachex.expire_at/4`
* Setting the `:expire` option within calls to `Cachex.put/4` or `Cachex.put_many/3`
* Setting the `:expire` option within return tuples in `Cachex.fetch/4` or `Cachex.get_and_update/4`

Each of these approches is handled the same way internally, they just provide sugar for various use cases. In general you should visit the appropriate functions for the documentation of how to use them, but here are some examples:


```elixir
import Cachex.Spec

# default for all entries
Cachex.start(:my_cache, [
    expiration: expiration(default: :timer.seconds(60))
])

# setting an expiration manually
Cachex.put(:my_cache, "key", "value")
Cachex.expire(:my_cache, "key", :timer.seconds(60))

# using the `Cachex.put/4` shorthand rather than setting manually
Cachex.put(:my_cache, "key", "value", expire: :timer.seconds(60))

# setting expiration on lazily computed values
Cachex.fetch(:my_cache, "key", fn ->
    { :commit, "value", expire: :timer.seconds(60) }
end)
```

There is no strong recommendation as to which you use, most of it falls to developer preference. The overhead of setting expirations is quite minimal, so feel free to take your pick. If you want the absolute fastest, inlining the `:expire` option against `Cachex.put/4` will be your best option.
