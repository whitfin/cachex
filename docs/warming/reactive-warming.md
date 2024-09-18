# Reactive Warming

The concept of reactive caching is the idea that a local cache is backed by another layer (for example something remote), meaning that on a cache miss you have another layer to look into to retrieve the data you want. As this lazily loads data into a cache, it's an effective tool for data which remains active for only a short period of time.

Reactive warmers are very memory efficient as they lazily load data on demand, instead of eagerly in anticipation of data access. This means that only actively required data is loaded into a cache. Pairing this with Cachex's expiration controls is a very common and effective way of modeling your caches.

## Defining a Fallback

The entry point to reactive caching is `Cachex.fetch/4`. You can pass a function to `Cachex.fetch/4`, and this function will only be executed if the key you're trying to access doesn't exist in the table. This function receives the name of the key being accessed, so you can define a common handler rather than inlining for every call.

```elixir
{ :ok, cache } = Cachex.start(:my_cache)
{ :commit, 3 } = Cachex.fetch(:my_cache, "key", &String.length/1)
```

When formatting results to place into the cache table, you must provide your results in the form of either `{ status, value }` or `{ status, value, options }`. These options should match the same what you'd use when calling `Cachex.put/3`, so check out the documentation if you need to.

In order to provide some degree of control over error handling, Cachex allows for either `:commit` or `:ignore` as a status. Values tagged with `:ignore` will just be returned without being stored in the cache, and those tagged with `:commit` will be returned after being stored in the cache. If you don't use a tagged Tuple return value, it will be assumed you're committing the value to help interoperability (as in the example above).

In previous versions of Cachex it was possible to store fallback `:state` within a cache (accessible as a second parameter to a fallback function). This has been removed as of v4.x to simplify `Cachex.fetch/4` handling and as it was a lesser used feature. It's possible this feature will be re-added in future if there is enough demand for it.

## Example Use Cases

Fallbacks allow you to build very simple bindings using a cache in order to reduce overhead on your backing systems. A very common use case is to use a `Cachex` instance with fallbacks to a remote system to lower the jumps across network. With effective use of expirations and fallbacks, you can ensure that your application doesn't receive stale data and yet minimizes network overhead and the number of remote operations.

The snippet below demonstrates an application using a cache to read from a remote database **at most** every 5 minutes, and retrieves the cached value from local memory in the meantime:

```elixir
# need our records
import Cachex.Spec

# initialize our cache with expiration set
Cachex.start_link(:my_cache, [
  expiration: expiration(default: :timer.minutes(5))
])

# retrieve a list of packages to serve via our API
Cachex.fetch(:my_cache, "/api/v1/packages", fn ->
  { :commit, Repo.all(from p in Package) }
end)
```

This allows you to easily lower the pressure on backing systems with very little code; a few lines can improve your API performance dramatically. The nice part about fallbacks is that they can easily be used with arbitrary data; something you can't predict in advance. Use cases based around input from a user (for example), are very well suited to using reactive caching (particularly because the data is only relevant when the user is currently active).

## Fallback Contention

As of Cachex v3.x fallbacks have changed quite significantly to provide the guarantee that only a single fallback will fire for a given key, even if more processes ask for the same key before the fallback is complete. The internal `Cachex.Services.Courier` service will queue these requests up, and then resolve them all with the results retrieved by the first. This ensures that you don't have stray processes calling for the same thing (which is especially bad if they're talking to a database, etc.). You can think of this as a per-key queue at a high level, with a short circuit involved to avoid executing too often.

To fully understand this with an example, consider this code (even if it is a little contrived):

```elixir
for i <- 0..2 do
  Cachex.fetch(:my_cache, "key", fn _ ->
    :timer.sleep(5000 + i)
    i
  end)
end
```

As each fallback function will take 5 seconds to execute, there will be 3 cache misses and therefore 3 processes each waiting 5 seconds (as the second and third calls are fired before the first call has resolved). This isn't ideal; in cases where you call a remote API or database you'd open 3 connections, asking for the same thing 3 times. The result of the code above would be that `"key"` has a value of `1`, then `2`, then `3` as each fallback returns and clobbers what was there previously.

The `Cachex.Service.Courier` will instead queue the second and third calls to fire _after_ the first one, rather than executing them all at once. Even better; the moment the first call resolves, the second and third will immediately resolve with the same results. This ensures that your function will only fire a single time, regardless of the number of processes awaiting the result. This helps with consistency in your application, while also reducing the overhead behind reactive caching.
