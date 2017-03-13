# Fallback Caching

The concept of fallback caching is the idea that a local cache is backed by another layer (typically something remote), meaning that on a cache miss you have another layer to look into to retrieve the data you want. Fallback functions can be defined on a cache at startup or on a call at runtime, and will only be executed if the key you're trying to retrieve doesn't exist locally. If you set a fallback at cache start up and then also pass one at call time, the call time definition takes precedence and will be executed instead. Each fallback receives a single argument by default; the key which resulted in a cache miss. Usually this will be available to you, but it allows for abstract fallback handling.

```elixir
# initializing a fallback on a cache at startup to be used on all cache misses
Cachex.start_link(:my_cache, [ fallback: &do_something/1 ])

# initializing a fallback at call time to retrieve on specific cache misses
Cachex.get(:my_cache, "key", [ fallback: &do_something/1 ])
```

There are also some cases in which you'll need a state to operate fallbacks, for example if you're caching responses from a database. In this case you might wish to have a database connection passed to your fallback to allow you to query it, and so Cachex allows you to pass a state at cache start which will be provided as a second argument to all fallback executions.

```elixir
# initializing a fallback on a cache at startup with a fallback state
Cachex.start_link(:my_cache, [ fallback: [ action: &do_something/2, state: db_conn ] ])

# fallbacks are always provided with the state, even at call time
Cachex.get(:my_cache, "key", fn(key, db_conn) ->
  DB.get(db_conn, key)
end)
```

### Common Use Cases

The combinations above allow you to build very simple bindings using a cache in order to reduce overhead on your backing systems. A very common use case is to use a Cachex instance with fallbacks to a remote system to lower the jumps across network. With effective use of expirations and fallbacks, you can ensure that your application doesn't receive stale data and yet minimizes network overhead and the number of remote operations.

Consider the snippet below:

```elixir
# initialize our cache with a database connection
Cachex.start_link(:my_cache, [
  default_ttl: :timer.minutes(5),
  fallback: [
    state: db_conn
  ]
])

# retrieve a list of packages to serve via our API
Cachex.get(:my_cache, "/api/v1/packages", fn(_key, db_conn) ->
  Database.load_packages(db_conn)
end)
```

This example demonstrates an application using a cache to read from a remote database **at most** every 5 minutes, and retrieves the cached value from local memory in the meantime. This allows you to esaily lower the pressure on backing systems with very little code; a few lines can improve your API performance dramatically.

### Expirations

If you wish to set an expiration on a value retrieved via a fallback execution, you can use the return value of your cache call to determine when it's appropriate. In the case your value was retrieved via a fallback, the first value in the returned Tuple will be the `:loaded` atom to signify that the value was loaded via a fallback. You can use this to conditionally set an expiration if you need to, but note that if your cache has a defined default TTL, it will be applied to fallback values automatically.

```elixir
# retrieve the value from the cache, match if loaded
with { :loaded, value } = res <- Cachex.get(:my_cache, "key") do
  # if so, set the key to expire after 5 minutes and return
  Cachex.expire(:my_cache, "key", :timer.minutes(5)) && res
end
```

### Handling Errors

The syntax shown above is a straightforward example of using a fallback which doesn't address the possibility of errors coming back from the database. In order to at least provide some degree of control over this, Cachex allows for `{ :commit | :ignore, value }` syntax. Rather than just returning a value in your fallback, you can return a Tuple tagged with either `:commit` or `:ignore`. Values tagged with `:ignore` will just be returned without being stored in the cache, and those tagged with `:commit` will be returned after being stored in the cache.

```elixir
Cachex.get(:my_cache, "/api/v1/packages", fn(_key, db_conn) ->
  case Database.load_package(db_conn) do
    { :ok, packages } -> { :commit, package }
    { :error, _reason } = error -> { :ignore, error }
  end
end)
```

If you don't use a tagged Tuple return value, it will be assumed you're committing the value (for backwards compatibility). In future this may change to enforce using a Tuple in order to reduce the amount of conditionals.
