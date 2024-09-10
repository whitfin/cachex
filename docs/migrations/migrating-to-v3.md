# Migrating to v3.x

There are many breaking changes bundled up in v3, and so this guide serves as a quick overview of what you'll probably need to check out during adoption. This won't focus on every change, just the user facing ones that can affect how your application code interacts with a cache. It also doesn't serve as a guide on how to change things, just pointing out on which areas the new documentation should be consulted on.

## Startup Options

In order to reduce a lot of the option parsing involved in Cachex, the options given to `Cachex.start_link/1` and `Cachex.start/1` have changed pretty drastically. The easiest way to see the differences is to look again at the documentation for these functions, but here's a very high level summary of changes (if these are things you use, please do check the docs):

- The `:commands` option now expects a list of `command` records.
- The `:default_ttl`, `:disable_ode` and `:ttl_interval` are now passed as an `expiration` record in the `:expiration` option (and have had their names changed).
- The `:ets_opts` option has been completely removed.
- The `:fallback` option now expects a `fallback` record.
- The `:hooks` option now expects a list of `hook` records.
- The `:limit` option now expect a `limit` record rather than a `%Cachex.Limit{}` (the shorthand of an integer is still valid).
- The `:record_stats` option has had the name changed simply to `:stats`.
- The `:transactions` option has also been renamed to `:transactional`.

All of these changes are based around improvements to the internal cache states and should also make it easier to understand the structures being passed around, whereas previously there were a lot of loose Keyword definitions. Please see either the module documentation, or guides for the feature you're using, for examples on how to use the new options.

## Fallbacks

Fallback caching has changed quite significantly in v3; there is no longer a `:fallback` option on calls to `get/3`, or any other calls which previously supported it. There are a few reasons for this, but the general one being that it was not always intuitive which calls did in fact support fallbacks. People consistently requested a feature that already existed, which means that it needed to be made more obvious. Due to this there will be a new `fetch/4` function in the main interface which replaces the behaviour. Going forward, the root term "fetch" will be used as synonymous to "fallback".

Here is an example of the previous v2.x branch vs. the same behaviour in the v3.x branch:

```elixir
# v2.x using the `:fallback` option to `get/3`.
Cachex.get(:my_cache, "key", fallback: &String.reverse/1)

# v3.x using the `fetch/4` signature.
Cachex.fetch(:my_cache, "key", &String.reverse/1)
```

The signature change allows for an explicit function in the API dedicated to lazy evaluation, and should hopefully be more approachable to those new to the project. It should be noted that the function being passed to `fetch/4` *is* optional if you have set a default fallback function in the main cache options.

## Hooks

### Interface

Hooks have changed pretty drastically, and yet they should be pretty close to what already exists. The main difference as of Cachex v3 is that Hooks are now driven by the behaviour a lot more than previously. When registering a hook on a cache, you now provide a `hook` record rather than a struct. These records consist of purely the hook module, the hook state, and an optional name to use to register the hook with. Everything else is now driven by behaviour functions in the module registered. This decision was taken as hooks remain fairly constant for a specific job, and so moving into the module definition makes a lot of sense.

Rather than define the changes here, please see the documentation for Hooks going forward. Generally the options from the old `%Cachex.Hook{}` struct have moved to have analogous functions in the module behaviour, but please check to be certain.

### Provisions

Nothing much to say here other than the previous `:worker` provision has been renamed over to `:cache` as the notion of cache workers is now redundant (and has been for a long time at this point). You can still use the received provision in the same way, it's just a tag change to make it clearer as to what is being delivered.

## Streams

Cache streams no longer accept the `:of` option, as it was oversimplifying exactly what was happening (and thus prone to error). However, you can now pass an ETS match specification as the second argument to filter internally in ETS before entering the stream. This is a small optimization, but also makes the developer think about matching more, rather than not appreciating exactly what was happening.

A happy side effect of this is that a stream will now respect the expiration time of records (at stream creation time), whereas before you could still receive expired records in the stream output (and would, regularly).

## Miscellaneous

### Automatic Janitor

The Janitor is enabled by default as of Cachex v3. It seems that explicitly turning it off is preferable to explicitly turning it on for the developer experience, as you tend to assume it's just running by default - and then you panic when nothing is being removed. Minor change, but technically incompatible so worth mentioning.

### Incr & Decr

Previously the `:amount` option dictated how much the value should be incremented/decremented by, but at this point it's an extra argument (the third parameter), which will default to `1`.

### Set vs. Put

This is a minor change, but worth mentioning. Going forward `set/4` has been replaced with `put/4`. This is nothing more than a name change, as @fishcakez rightfully pointed out that `put/4` is a better naming convention for Elixir. The old `set/4` has been deprecated and simply forwards to `put/4`, so you should likely migrate to avoid that extra function hop :).

### Statistics

The format of the map being returned from `Cachex.stats/2` has been modified due to some normalization which took place; this will look much clearer and adopts snake_case over camelCase (etc). It also correctly tracks custom invocations at this point, rather than ignoring them (like it did previously).

### Missing Values

In earlier versions of Cachex, `{ :missing, nil }` would be returned to signal that a value did not exist in the cache. This has been removed to simply return `{ :ok, nil }` because (believe it or not) the overhead of figuring out if something was missing was actually quite large in some cases. If you need the same behaviour, you should avoid setting `nil` explicitly in your cache and put something else in instead - that way `{ :ok, nil }` is semantically the same as `{ :missing, nil }`.
