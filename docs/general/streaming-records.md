# Streaming Records

Cachex provides the ability to create an Elixir `Stream` seeded by the contents of a cache, using an ETS table continuation and `Stream.resource/3`. This then allows the developer to use any of the `Enum` or `Stream` module functions against the entries in cache, which can be a very powerful and flexible tool.

## Basic Streams

By default, `Cachex.stream/3` will return a `Stream` over all entries in a cache which are yet to expire (at the time of stream creation). These cache entries will be streamed as `Cachex.Spec.entry` records, so you can use pattern matching to pull any of the entry fields assuming you have `Cachex.Spec` imported:

```elixir
# for matching
import Cachex.Spec

# store some values in the cache
Cachex.start(:my_cache)
Cachex.put(:my_cache, "one", 1)
Cachex.put(:my_cache, "two", 2)
Cachex.put(:my_cache, "three", 3)

# == 6
:my_cache
|> Cachex.stream!()
|> Enum.reduce(0, fn entry(value: value), total ->
  total + value
end)
```

## Efficient Querying

While the `Enum` module provides the ability to filter records easily, we can do better by pre-filtering using a match specification. Under the hood these matches are as defined by the Erlang documentation, and can be passed as the second argument to `Cachex.stream/3`.

To avoid having to handle Cachex implementation details directly, the `Cachex.Query` module exposes a few functions designed to assist with creation of new queries. If we take our example above, we can use a query to sum only the odd numbers in the table without having to filter on the Elixir side:

```elixir
# for matching
import Cachex.Spec

# store some values in the cache
Cachex.start(:my_cache)
Cachex.put(:my_cache, "one", 1)
Cachex.put(:my_cache, "two", 2)
Cachex.put(:my_cache, "three", 3)

# generate our filter to find odd values
filter = {:==, {:rem, :value, 2}, 1}

# generate the query using the filter, only return `:value
query = Cachex.Query.build(where: filter, output: :value)

# == 4
:my_cache
|> Cachex.stream!(query)
|> Enum.sum()
```

Rather than retrieve and handle the whole cache entry, here we're using `:output` to choose only the `:value` column from each entry. This lets us skip out on `Enum.reduce/3` and go directly to `Enum.sum/1`, much easier!

It's important  to note here is that cache queries do *not* distinguish between expired records in a cache; they match across all records within a cache. This is a change in Cachex v4.x to provide more flexibility in other areas of the Cachex library. If you want to filter out expired records, you can use the `Cachex.Query.expired/1` convenience function:

```elixir
# for matching
import Cachex.Spec

# store some values in the cache
Cachex.start(:my_cache)
Cachex.put(:my_cache, "one", 1)
Cachex.put(:my_cache, "two", 2)
Cachex.put(:my_cache, "three", 3)

# generate our filter to find odd values
filter = {:==, {:rem, :value, 2}, 1}

# wrap our filter to filter expired values
filter = Cachex.Query.expired(filter)

# generate the query using the filter, only return `:value
query = Cachex.Query.build(where: filter, output: :value)

# == 4
:my_cache
|> Cachex.stream!(query)
|> Enum.sum()
```

This function accepts a query guard and wraps it with clauses to filter out expired records. The returned guard can then be passed to `Cachex.Query.build/1` to return only the expired records which match your query. This is all fairly simple, but it's definitely something to keep in mind when working with `Cachex.Query`!
