# Cache Limits

Cache limits are restrictions on a cache to ensure that it stays within given bounds. Currently these limits are based around the number of entries inside a cache, but there are plans to add new policies in future (for example basing the limits on memory spaces).

## Configuration

Limits are defined at cache startup and cannot be changed at this point in time. You can provide either an integer or a `limit` record to the `:limit` option in the Cachex interface.

```elixir
# include records
import Cachex.Spec

# maximum 500 entries, default eviction, default trim
Cachex.start(:my_cache, [ limit: 500 ])

# maximum 500 entries, LRW eviction, trim to 250
Cachex.start(:my_cache, [ limit: limit(size: 500, policy: Cachex.Policy.LRW, reclaim: 0.5) ])
```

A `limit` record consists (currently) of only 4 fields which dictate a limit and how it should be enforced. This allows the user to customize their eviction without getting too low-level. Below is an example structure, which demonstrates what an integer `:limit` parameter would unpack to internally.

```elixir
limit(
  # the limit provided
  size: 500,
  # the policy to use for eviction
  policy: Cachex.Policy.LRW,
  # how much to reclaim on bound expiration
  reclaim: 0.1,
  # options to pass to the policy
  options: []
}
```

To expound a little on the above, it defines that the cache should aim to store no more than `500` entries (which is user defined). If the cache key space goes above this number, it should evict `50` of the entries in the cache as chosen by the provided `:policy`. The amount `50` is dictated by the `:reclaim` option, which is essentially a percentage of the cache to evict on hitting the bounds. This value much match `1 >= value >= 0` in order to be accepted and override the default (due to being a percentage).

## Policies

The policy `Cachex.Policy.LRW` above is a built-in Cachex eviction policy which removes the oldest values first. This means that we calculate the first `N` oldest entries, where `N` is roughly equal to `limit * reclaim`, and remove them from the cache in order to make room for new entries. It should be noted that "oldest" in this context means "those written or updated longest ago". This is currently the only policy implemented within Cachex, although it's likely that more will follow (and you can write them yourself too).

You should be aware that eviction is not instant - it happens in reaction to events which are additive to the cache and is extremely quick, however if you have a cache limit of 500 keys and you add 500,000 keys, the cleanup does take a few hundred milliseconds to occur (that's a lot to clean). This shouldn't affect most users, but it is something to point out and be aware of.

It should be noted that although LRW is the only policy implemented at this time, you can control LRU policies by using `Cachex.touch/2` to do a write on a key without affecting the value or TTL. Using `Cachex.touch/2` alongside the LRW policy is likely how an LRU policy would work regardless.
