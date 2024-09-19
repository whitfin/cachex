# Limiting Caches

Cache limits are restrictions on a cache to ensure that it stays within given bounds. The limits currently shipped inside Cachex are based around the number of entries inside a cache, but there are plans to add new policies in future (for example basing the limits on memory spaces). You even even write your own!

## Manual Pruning

The main entrypoint to cache limitation included in Cachex is `Cachex.prune/3`, which provides a Least Recently Written (LRW) implementation of pruning a cache. This means that we calculate the first `N` oldest entries, where `N` is roughly equal to `limit * reclaim`, and remove them from the cache in order to make room for new entries. It should be noted that "oldest" in this context means "those written or updated longest ago".

You can trigger a pruning manually via `Cachex.prune/3`, passing the maximum size of a cache to shrink to:

```elixir
# start a new cache
Cachex.start(:my_cache)

# insert 100 keys
for i <- 1..100 do
  Cachex.put!(:my_cache, i, i)
end

# guarantee we have 100 keys in the cache
{ :ok,  100 } = Cachex.size(:my_cache)

# trigger a pruning down to 50 keys only
{ :ok, true } = Cachex.prune(:my_cache, 50, reclaim: 0)

# verify that we're down to 50 keys
{ :ok,   50 } = Cachex.size(:my_cache)
```

The `:reclaim` option can be used to reduce thrashing, by evicting an additional number of entries. In the case above the next write would cause the cache to once again need pruning, and then so on. The `:reclaim` option accepts a percentage (as a decimal) of extra keys to evict, which gives us a buffer between pruning of a cache.

To demonstrate this we can run the same example as above, except using a `:reclaim` of `0.1` (the default). This time we'll be left with 45 keys instead of 50, as we reclaimed an extra 10% of the table (`50 * 0.1 = 5`):

```elixir
# start a new cache
Cachex.start(:my_cache)

# insert 100 keys
for i <- 1..100 do
  Cachex.put!(:my_cache, i, i)
end

# guarantee we have 100 keys in the cache
{ :ok,  100 } = Cachex.size(:my_cache)

# trigger a pruning down to 50 keys, reclaiming 10%
{ :ok, true } = Cachex.prune(:my_cache, 50, reclaim: 0.1)

# verify that we're down to 45 keys
{ :ok,   45 } = Cachex.size(:my_cache)
```

It is almost never a good idea to set `reclaim: 0` unless you have very specific use cases, so if you don't it's recommended to leave `:reclaim` at the default value - it was only used above for example purposes.

## Lifecycle Pruning

Although you can manually prune a cache, in reality this isn't particularly useful as you want to be able to continually monitor a cache's size. For this reason, Cachex includes several lifecycle hooks to trigger `Cachex.Limit` automatically. This will give you a monitored cache size, easily configured at cache startup:

```elixir
# include records
import Cachex.Spec

# maximum 500 entries, LRW eviction, default trim
Cachex.start(:my_cache,
  hooks: [
    hook(module: Cachex.Limit.Scheduled, args: {
      500,  # setting cache max size
      [],   # options for `Cachex.prune/3`
      []    # options for `Cachex.Limit.Scheduled`
    })
  ]
)
```

This will spawn a cache hook to continually prune your cache periodically, based on the options you provided. You can pass options for `Cachex.prune/3` as the second element of the `args` tuple, and customize the hook itself in the third element. Currently the only supported parameter for the hook is `:frequency`, which defaults to `1000` (one second). Please see the documentation for an updated list of supported configuration.

If you need more exact timing you can opt to use `Cachex.Limit.Evented` rather than `Cachex.Limit.Scheduled`, which will react to hook events inside a cache instead of running on a schedule:

```elixir
# include records
import Cachex.Spec

# maximum 500 entries, LRW eviction, default trim
Cachex.start(:my_cache,
  hooks: [
    hook(module: Cachex.Limit.Evented, args: {
      500,  # setting cache max size
      []    # options for `Cachex.prune/3`
    })
  ]
)
```

This is a much more accurate policy, but has a much higher memory and CPU overhead due to hooking into the main lifecycle events. If you can, it's recommended to use the scheduling approach for this reason.

It should be hopefully be evident from the above, but lifecycle pruning is not instant - in general it is extremely quick, however if you have a cache limit of 500 keys and you add 500,000 keys, the cleanup does take a few hundred milliseconds to occur (that's a lot to clean). This shouldn't affect most users, but it is something to point out and be aware of.

## LRU Style Pruning

In addition to the two lifecycle controls for LRW based caching, Cachex v4.x also includes a naive solution for those who wish to use Least Recently Used (LRU) based approaches via `Cachex.Limit.Accessed`.

This is done as an extension of LRW caching by attaching a small lifecycle hook to update the access time of each record, thus making the existing LRW hooks able to handle them as usual. Due to this you can freely choose either of the two LRW approaches above, by placing the LRW access hook *before* it in the cache initialization:

```elixir
# include records
import Cachex.Spec

# maximum 500 entries, LRW eviction, default trim
Cachex.start(:my_cache,
  hooks: [
    hook(module: Cachex.Limit.Accessed),
    hook(module: Cachex.Limit.Scheduled, args: {
      500,  # setting cache max size
      [],   # options for `Cachex.prune/3`
      []    # options for `Cachex.Limit.Scheduled`
    })
  ]
)
```

As you might expect, there is a fair cost to this as `Cachex.Limit.Accessed` must listen to and act on cache events when a key is accessed. This can result in heavy read/write activity within a cache. For this reason it's recommended to operate using LRW when possible, and LRU only as absolutely necessary.
