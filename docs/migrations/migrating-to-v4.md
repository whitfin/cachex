# Migrating to v4.x

The release of Cachex v4.x includes a lot of internal cleanup and restructuring. As such, there are quite a few breaking changes to be aware of.

Some of them are simple (like changing names) and others require more involved migration. This page will go through everything and hopefully make it easy for you to upgrade!

## Cache Options

There are a number of changes to the options provided at cache startup in `Cachex.start_link/2`.

The `:fallback` option has been removed. This was introduced in earlier versions of Cachex before `Cachex.fetch/4` existed, and it doesn't serve nearly as much purpose anymore. Removing this cleaned up a lot of the internals and removes a lot of hidden magic, so it was time to go. To align with this change, the function parameter of `Cachex.fetch/4` has been changed to be required rather than optional.

Both the `:stats` and `:limit` options have been removed, in favour of explicitly providing the hooks that back them. These flags were sugar in the past but caused noise and confusion, and it's now much better to have people getting used to using `:hooks`:

```elixir
# behaviour in Cachex v3
Cachex.start_link(:my_cache, [
    stats: true,
    limit: limit(
        size: 500,
        policy: Cachex.Policy.LRW,
        reclaim: 0.5,
        options: []
    )
])

# behaviour in Cachex v4
Cachex.start_link(:my_cache, [
    hooks: [
        hook(module: Cachex.Stats),
        hook(module: Cachex.Limit.Scheduled, args: {
            500,  # setting cache max size
            [],   # options for `Cachex.prune/3`
            []    # options for `Cachex.Limit.Scheduled`
        })
    ]
])
```

Both of these features have had additional documentation written, so you can double check the relevant documentation in [Gathering Stats](../management/stats-gathering.md) and [Limiting Caches](../management/limiting-caches.md) as necessary. Limits in particular have had quite a shakeup in Cachex v4, so it's definitely worth a visit to the documentation if you're using those!

In the example above, you can also see that the `:state` option of a hook definition has been replaced with `:args` in Cachex v4.x. As a hook controls the state during execution, this is to separate it from warmers where `:state` is static.

The `:nodes` option has also been removed, in favour of the new approach to routing in a distributed cache. It's possible to keep the same semantics as Cachex v3 using the `Cachex.Router.Jump` module implementation:

```elixir
# behaviour in Cachex v3
Cachex.start_link(:my_cache, [
    nodes: [
        :node1,
        :node2,
        :node3
    ]
])

# behaviour in Cachex v4
Cachex.start_link(:my_cache, [
    router: router(module: Cachex.Router.Jump, options: [
        nodes: [
            :node1,
            :node2,
            :node3
        ]
    ])
])
```

This is covered in much more detail in the corresponding documentation of [Cache Routers](../routing/cache-routers.md) and [Distributed Caches](../routing/distributed-caches.md); it's heavily recommended you take a look through those pages if you were using `:nodes` in the past.

Last but not least, the `:transactional` flag has been renamed to `:transactions`. Ironically this used to be the name in the Cachex v2 days, but it turned out that it was a mistake to change it in Cachex v3!

## Return Value Change

The return value for `Cachex.fetch/4` has changed. When `fetch/4` is given a fallback function that returns a three-element tuple 
(like `{ :commit, String.reverse(key), expire: :timer.seconds(60) }`), it returns a two-element tuple isntead of a three-element tuple.

Typespec for `fetch/4` prior to 4.X:

```elixir
@spec fetch(cache(), any(), function() | nil, Keyword.t()) ::
  {status() | :commit | :ignore, any()} | {:commit, any(), any()}
```

Typespec for `fetch/4` in 4.X:

```elixir
@spec fetch(Cachex.t(), any, function(), Keyword.t()) ::
  {status | :commit | :ignore, any}
```

## Warming Changes

There are some minor changes to cache warmers in Cachex v4, which require only a couple of minutes to update.

The `:async` field inside a warmer record has been replaced with the new `:required` field. This is basically equivalent to the inverse of whatever you would have set `:async` to in the past. As cache warmers can now be fired as either async or sync on the fly, this option didn't make much sense anymore. Instead the new `:required` field dictates that a warmer is _required_ to have run before a cache is considered fully started.

The other change affecting cache warmers is the removal of `interval/0` function from the `Cachex.Warmer` behaviour. The interval is something you might want to change dynamically, and so it didn't make sense to be defined in the code itself. It has been moved to the `:interval` field in the Cachex warmer record, and behaves exactly as before.

## Function Parameters

There are several naming changes to options passed to functions across the Cachex API. There are no functional differences, so these should be quick cosmetic things to change as needed.

First of all the `:ttl` option has been renamed to `:expire` in all places it was supported (mainly `Cachex.put/4` and various wrappers). It was strange to refer to expiration as "expiration" all over and have the setting be `:ttl`, so this just makes things more consistent.

The `:initial` option for `Cachex.incr/4` and `Cachex.decr/4` has been renamed to `:default`. This makes way more sense and is much more intuitive; it was probably just a misnaming all those years ago that stuck. Time to make it better!

For all of the functions which support `:batch_size`, namely `Cachex.stream/3` and functions which use it, this has now been renamed to `:buffer`. The previous name was too close to the underlying implementation, whereas the new name is much more generic (and shorter to type!).

## Removed & Renamed APIs

There are several changes to the main Cachex API, including removal of some functions and naming changes of others.

The `count/2` function has been removed in favour of `Cachex.size/2`. These two functions did almost the same thing, the only difference was that `Cachex.size/2` would return the size of the cache including unpurged expired records, while `count/2` would filter them out. Instead of two functions for this, you can now opt into this via `Cachex.size/2`:

```elixir
# total cache entry count
Cachex.size(:my_cache)
Cachex.size(:my_cache, expired: true)

# ignores expired but unremoved entries
Cachex.size(:my_cache, expired: false)
```

This should hopefully feel more intuitive, while allowing us to trim a bunch of the Cachex internals. The underlying implementations are identical, so it should be easy to migrate if you need to.

Both functions `dump/3` and `load/3` have been renamed in Cachex v4. These names were terrible to begin with, so it's about time they're changed! Instead we now have `Cachex.save/3` and `Cachex.restore/3`, which behave in exactly the same way (aside from being a bit cleaner in implementation!). The only major difference here is that `Cachex.restore/3` will return a count of restored documents, rather than simply `true`.

Finally the two deprecated functions `set/4` and `set_many/3` have finally been removed. If you were using these, please use `Cachex.put/4` and `Cachex.put_many/3` instead from now on.

## Other Miscellaneous Changes

There are a few other small changes which don't really need much explanation, but do need to be noted for reference.

The minimum supported Elixir version has been raised from Elixir 1.5 to Elixir 1.7. In reality there are probably very few people out there still using Elixir 1.7 and it could be raised further, but there's also nothing really compelling enough to make this happen at this time.

A lot of the record types in Cachex v4 had their orders changed, so if anyone was matching directly (instead of using record syntax) they should adapt to using `entry(entry, :field)` instead.

The former `ExecutionError` has been replaced with `Cachex.Error`, which is a combination of several smaller modules. This is just a naming difference to hopefully make it easier to type and remember!
