# Gathering Statistics

Cachex includes basic support for tracking statistics in a cache, so you can look at things like throughput and hit/miss rates. This is provided via the `Cachex.Stats` hook implementation.

## Configuration

As of Cachex v4.x this is configured as a hook during cache initialization:

```elixir
# include records
import Cachex.Spec

# create a cache with stats
Cachex.start(:my_cache,
  hooks: [
    hook(module: Cachex.Stats)
  ]
)

# insert 100 keys
for i <- 1..100 do
  Cachex.put!(:my_cache, i, i)
end

# generate both a cache hit and a miss
{ :ok,   1 } = Cachex.get(:my_cache, 1)
{ :ok, nil } = Cachex.get(:my_cache, 101)

# print stats
:my_cache
|> Cachex.stats!()
|> IO.inspect
```

Running this will give you a map of various statistics based on the actions and operations taken by your cache.

## Example Statistics

The statistics map returned by `Cachex.stats/2` should look something like the example below (at the time of writing):

```elixir
%{
  meta: %{creation_date: 1726777631670},
  hits: 1,
  misses: 1,
  hit_rate: 50.0,
  miss_rate: 50.0,
  calls: %{get: 2, put: 100},
  operations: 102,
  writes: 100
}
```

As you can see, we see the breakdown of calls to the cache, the hit/miss rate, the total writes to a cache, etc. This is useful when gauging how much time your cache is actually saving and allows you to determine that everything is working as intended.

It should be noted that the output format of `Cachex.stats/2` is *not* considered part of the Public API for backwards compatibility; the shape of this may change as and when it's necessary to do so.
