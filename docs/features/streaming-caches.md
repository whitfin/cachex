# Streaming Caches

Cachex provides the ability to return an Elixir `Stream` based on the contents of a cache, which is built using a table cursor and `Stream.resource/3`. This allows you to use any of the `Enum` or `Stream` module functions on the entries in a cache, which can be very powerful. By default, `Cachex.stream/3` will return a stream over all entries in a cache which are yet to expire (at the time of stream creation). They will be streamed as `entry()` records, and you can match and do all of the typical record stuff to them assuming you have `Cachex.Spec` imported:

```elixir
# for matching
import Cachex.Spec

# store some values in the cache
Cachex.put(:my_cache, "one", 1)
Cachex.put(:my_cache, "two", 2)
Cachex.put(:my_cache, "three", 3)

# 6
:my_cache
|> Cachex.stream!
|> Enum.reduce(0, fn(entry(value: value), total) ->
    total + value
   end)
```

## Complex Streaming

While the `Enum` module provides the ability to filter records easily, you can optimize using a match specification. This is a match specification as defined by the Erlang documentation (Cachex does little modification here), and can be passed as the second argument to `Cachex.stream/3` to filter. For your convenience, `Cachex.Query` exposes a few functions designed to assist with query creation. If we take the example above, we can use a query to only sum the odd numbers, without having to filter on the Elixir side, where it would be slower:

```elixir
# for matching
import Cachex.Spec

# store some values in the cache
Cachex.put(:my_cache, "one", 1)
Cachex.put(:my_cache, "two", 2)
Cachex.put(:my_cache, "three", 3)

# generate our filter to find odd values
filter = { :==, { :rem, :value, 2 }, 1 }

# generate the query using the filter
query = Cachex.Query.create(filter, :value)

# 4
:my_cache
|> Cachex.stream!(query)
|> Enum.sum
```

Couple of things to mention here; first of all, you can use any of the `entry()` field names in your matches, and they'll be substituted out automatically. In this case we use `:value` in our filter, which would compile down to `:"$4"` instead. You might also have noticed that we can jump directly to `Enum.sum/1` here. The second (optional) argument to `create/2` controls the format of the stream elements, in this case just streaming the `:value` field of the entry. If the second argument is not provdided, it'll stream entry records (just like the first example). It should be noted that `Cachex.Query.create/2` will automatically bind a filter clause to filter out expired documents. If you wish to run a query on the entire dataset, you can use `Cachex.Query.raw/2` instead.
