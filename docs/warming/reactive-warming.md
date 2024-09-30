# Reactive Warming

Warming a cache reactively is essentially lazily loading a missing key on access. Put another way, Cachex will "react" to a missing key by attempting to load it from elsewhere (and then place it in the cache). This is a fairly common need, and lends itself well to a couple of different situations:

* Sporadic calls may result in a saving of resources:
  * As data is warmed "on demand", we only use cache memory when necessary.
  * There is no wasted cache operation time warming data needlessly.
* Parameterized calls may result in a short lived window of hot data, such as:
  * A user session focuses on specific resources often for a brief period of time.
  * A window of data which is relevant for a brief period of time (i.e. last 60 minutes).

As data is loaded lazily, this is a very effective approach for data which remains active for only a short period of time. This also means that reactive warmers are very memory efficieny by default, because they load data as it's needed instead of eagerly in anticipation of it being needed.

## Defining a Warmer

To provide this type of warming, Cachex provides the interface function `Cachex.fetch/4`. When calling this action, the developer provides a function containing the code to run in case of a cache miss. The result of this function is used to populate the key in the cache.

There are several formats you can use to return values from a warming function. The snippet below demonstrates the various recognised return types from a warming function inside `Cachex.fetch/4`.

```elixir
# start an empty cache
Cachex.start(:cache)

# defining a function alias using shorthand syntax
{ :commit, 4 } = Cachex.fetch(:cache, "key1", &String.length/1)
{     :ok, 4 } = Cachex.fetch(:cache, "key1", &String.length/1)

# defining an inline function using `:commit` syntax
{ :commit, 4 } = Cachex.fetch(:cache, "key2", fn key ->
  { :commit, String.length(key) }
end)

# defining an inline function using `:commit` syntax, with options
{ :commit, 4 } = Cachex.fetch(:cache, "key3", fn key ->
  { :commit, String.length(key), expire: :timer.seconds(60) }
end)

# define a function which doesn't save the result (i.e. in case of error)
{ :ignore, 4 } = Cachex.fetch(:cache, "key4", fn key ->
  { :ignore, String.length(key) }
end)
```

There are a few things to point out here explicitly. Firstly, the return value of a call to `Cachex.fetch/4` will contain `:commit` only if the value was loaded by that specific call. If the value already exists in the table, the `:ok` value will be returned instead. As we can see above, we loaded `key1` twice and so the second call received `:ok` as it was already populated.

In the case of `key3` we're providing options alongside our commit tuple. This is a recent feature which allows us to pass options directly through to `Cachex.put/4` (which `Cachex.fetch/4` uses internally). This means that you're now able to define things like expiration as a function of a lazily loaded value, which is a very flexible model.

Finally the use of `:ignore` in the return tuple allows the developer to opt out of placing the value in the cache. This is useful when handling errors, or cases where data isn't ready for consumption yet. You can still pass a value back to the outer code flow here, it just won't be placed inside the cache.

In previous versions of Cachex it was possible to store fallback `:state` within a cache (accessible as a second parameter to a fallback function). This has been removed as of v4.x to simplify `Cachex.fetch/4` handling and as it was a lesser used feature. It's possible this feature will be re-added in future if there is enough demand for it.

## Example Use Cases

The use of these warmers allows you to build very simple bindings to reduce overhead on your backing systems. A very common use case is using a `Cachex` instance with reactive warming from a remote system, in order to lower the number of network jumps. With effective use of other cache features such as expiration, you can ensure that your application finds a good balance between avoiding stale data and minimization of network overhead.

As an example, let's look an application containing an API to retrieve a list of packages in a database. As creation of a package is infrequent, we can avoid calling our remote database every time and instead retrieve a cached value from memory:

```elixir
# need our records
import Cachex.Spec

# initialize our cache with expiration set
Cachex.start_link(:cache, [
  expiration: expiration(default: :timer.minutes(5))
])

# retrieve a list of packages to serve via our API
Cachex.fetch(:cache, "/api/v1/packages", fn ->
  { :commit, Repo.all(from p in Package) }
end)
```

The combination of options here (even in this small snippet) means that we'll only call our database **at most** once every 5 minutes. This allows you to easily lower the pressure on backing systems with very little code; a few lines can improve your API performance dramatically!

## Warmer Contention

One of the most common missteps with warming reactive like this is how an application behaves when a missing key is read concurrently from two places. Cachex makes sure to take these cases into account to guarantee consistency in your application. For a moment, let's forget that `Cachex.fetch/4` exists and instead write a manual example which demonstrates a couple of issues:

```elixir
# start a new cache
Cachex.start(:cache)

# lazily load a missing value
case Cachex.get(:cache, "key") do
  {:ok, nil} ->
    value = call_database_with_network_delay("key")
    Cachex.put(:cache, "key", value)
    value

  value ->
    value
end
```

At a glance this might look fine, but there's one big problem with this approach. As `call_database_with_network_delay/1` takes a long time to run, there's still a period of time in which our key is missing from a cache. This has the nasty side effect that any calls made to this same code between the initial call and the time when `call_database_with_network_delay/1` first returns will spawn additional calls to the database!

Fortunately Cachex's design will ensure that only the _first_ warmer executed will fire for a given key, even if more processes ask for the same key before the code completes. The internal Cachex `Courier` service will queue these requests up, and then resolve them all with the result produced by the first. This ensures that you don't have stray processes calling for the same thing (which is especially bad if they're talking to a database, etc.).

You can think of this as a per-key queue at a high level, with a short circuit involved to avoid executing too often. To see this in action, let's attempt to fetch a key ten times using both our manual approach, as well as using `Cachex.fetch/4`:

```elixir
# start a new cache
Cachex.start(:cache)

# run manually
for _ <- 1..10 do
  spawn(fn ->
    case Cachex.get(:cache, "key1") do
      {:ok, nil} ->
        IO.puts("Running warmer after get/2")
        value = :timer.sleep(1000)
        Cachex.put(:cache, "key1", value)
        value

      value ->
        value
    end
  end)
end

# run via fetch/4
for _ <- 1..10 do
  spawn(fn ->
    Cachex.fetch(:cache, "key2", fn key ->
      IO.puts("Running warmer in fetch/4")
      value = :timer.sleep(1000)
      value
    end)
  end)
end
```

If you run this code, you'll see the log of the first loop emit 10 times as each call overlaps and you end up with `:timer.sleep/1` called 10 times. In the second loop you'll only see the log emit a single time, as Cachex knows to queue the subsequent calls to resolve with the result of the first.
