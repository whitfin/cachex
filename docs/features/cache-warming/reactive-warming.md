# Reactive Warming

## Overview

The concept of fallback caching is the idea that a local cache is backed by another layer (typically something remote), meaning that on a cache miss you have another layer to look into to retrieve the data you want. Fallback functions can be defined on a cache at startup or on a call at runtime, and will only be executed if the key you're trying to retrieve doesn't exist locally. If you set a fallback at cache start up and then also pass one at call time, the call time definition takes precedence and will be executed instead. Each fallback receives a single argument by default; the key which resulted in a cache miss. Usually this will be available to you, but it allows for abstract fallback handling.

```elixir
# need our records
import Cachex.Spec

# initializing a fallback on a cache at startup to be used on all cache misses
Cachex.start_link(:my_cache, [ fallback: fallback(default: &do_something/1) ])

# initializing a fallback at call time to retrieve on specific cache misses
Cachex.fetch(:my_cache, "key", &do_something/1)
```

There are also some cases in which you'll need a state to operate fallbacks, for example if you're caching responses from a database. In this case you might wish to have a database connection passed to your fallback to allow you to query it, and so Cachex allows you to pass a state at cache start which will be provided as a second argument to all fallback executions.

```elixir
# need our records
import Cachex.Spec

# initializing a fallback on a cache at startup with a fallback state
Cachex.start_link(:my_cache, [ fallback: fallback(action: &do_something/2, state: db_conn) ])

# fallbacks are always provided with the state, even at call time
Cachex.fetch(:my_cache, "key", fn(key, db_conn) ->
  case Database.load_package(db_conn) do
    { :ok, packages } -> { :commit, packages }
    { :error, _reason } = error -> { :ignore, error }
  end
end)
```

In order to provide some degree of control over error handling, Cachex allows for `{ :commit | :ignore, value }` syntax being returned from a fallback. Rather than just returning a value in your fallback, you can return a Tuple tagged with either `:commit` or `:ignore`. Values tagged with `:ignore` will just be returned without being stored in the cache, and those tagged with `:commit` will be returned after being stored in the cache. If you don't use a tagged Tuple return value, it will be assumed you're committing the value (for backwards compatibility). In future this may change to enforce using a Tuple in order to reduce the amount of conditionals.

## Courier

As of v3, fallbacks changed quite significantly to provide the guarantee that only a single fallback will fire for a given key, even if more processes ask for the same key before the fallback is complete. The internal `Courier` service will queue these requests up, then resolve them all with the results retrieved by the first. This ensures that you don't have stray processes calling for the same thing (which is especially bad if they're talking to a database, etc.). You can think of this as a per-key queue at a high level, with a short circuit involved to avoid executing too often.

To fully understand this, consider this code in Cachex v2.x (even if it is a little contrived):

```elixir
for i <- 0..2 do
  Cachex.get(:my_cache, "key", fallback: fn _ ->
    :timer.sleep(5000 + i)
    i
  end)
end
```

As the fallbacks each take 5 seconds, you have 3 cache misses and therefore 3 processes each waiting 5 seconds (as the second and third calls are fired before the first call has resolved). This isn't great, because if your fallback is a database, you'd hit it 3 times here, asking for the same thing each time. The result of the code above would be that `"key"` has a value of `1`, then `2`, then `3` as each fallback returns and clobbers what was there previously.

The new `Courier` service in Cachex v3 will actually queue the second and third calls to fire after the first one, rather than firing them all at once. What's even better; the moment the first call resolves, the second and third will immediately resolve with the same results. This ensures that your fallback only fires a single time, regardless of the number of processes awaiting the result. This change in behaviour means that the code above would result in `"key"` having a single value of `1` as the second and third never fire. Although this results in a behaviour change above, it should basically never affect you in the same way as the code above is deliberately designed to highlight the changes.

## Expirations

Sometimes you might want to set an expiration based on a value retrieved via a fallback execution. For this case, as of Cachex v3.6.0, you can (finally) provide expiration options in your returned `:commit` tuple.

```elixir
Cachex.fetch(:my_cache, "key", fn ->
  { :commit, do_something(), expire: :timer.seconds(60) }
end)
```

This inlining is faster than previous solutions, while maintaining correctness and being easy to use. If you are using an older version of Cachex, you can conditionally assign an expiration based on the return value of your cache call in the case of a cache `:commit`:

```elixir
# retrieve the value from the cache, match if loaded
with { :commit, value } = res <- Cachex.fetch(:my_cache, "key") do
  # if so, set the key to expire after 5 minutes and return
  Cachex.expire(:my_cache, "key", :timer.minutes(5)) && res
end
```

Also note that if your cache has a defined default TTL, it will be applied to fallback values automatically.

## Use Cases

Fallbacks allow you to build very simple bindings using a cache in order to reduce overhead on your backing systems. A very common use case is to use a `Cachex` instance with fallbacks to a remote system to lower the jumps across network. With effective use of expirations and fallbacks, you can ensure that your application doesn't receive stale data and yet minimizes network overhead and the number of remote operations.

The snippet below demonstrates an application using a cache to read from a remote database **at most** every 5 minutes, and retrieves the cached value from local memory in the meantime:

```elixir
# need our records
import Cachex.Spec

# initialize our cache with a database connection
Cachex.start_link(:my_cache, [
  expiration: expiration(default: :timer.minutes(5))
  fallback:   fallback(state: db_conn)
])

# retrieve a list of packages to serve via our API
Cachex.fetch(:my_cache, "/api/v1/packages", fn(_key, db_conn) ->
  Database.load_packages(db_conn)
end)
```

This allows you to easily lower the pressure on backing systems with very little code; a few lines can improve your API performance dramatically. The nice part about fallbacks is that they can easily be used with arbitrary data; something you can't predict in advance. Use cases based around input from a user (for example), are very well suited to using reactive caching (particularly because the data is only relevant when the user is currently active).
