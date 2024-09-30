# Proactive Warming

Introduced alongside Cachex v3, cache warmers act as an eager way to populate a cache. Rather than waiting for a cache miss to retrieve a value, values will be pulled up front to ensure that there is never a miss. This can be viewed as being _proactive_, whereas `Cachex.fetch/4` can be seen as _reactive_. As such, this is a better tool for those who know what data will be requested, rather than those dealing with arbitrary data.

## Defining a Warmer

To implement this type of warming, Cachex introduced the [Cachex.Warmer](https://hexdocs.pm/cachex/Cachex.Warmer.html) behaviour. This behaviour can be implemented on a module to define the logic you want to run periodically in order to refresh your data from a source. Let's look at defining a very typical proactive warmer, which fetches rows from a database and maps them into a cache table using the `id` field as the cache key:

```elixir
defmodule MyProject.DatabaseWarmer do
  @moduledoc """
  Dummy warmer which caches database rows.
  """
  use Cachex.Warmer

  @doc """
  Executes this cache warmer with a connection.
  """
  def execute(connection) do
    connection
    |> Database.query
    |> handle_results
  end

  # ignores the warmer result in case of error
  defp handle_results({ :error, _reason }),
    do: :ignore

  # maps the results into pairs to store
  defp handle_results({ :ok, rows }) do
    { :ok, Enum.map(rows, fn(row) ->
      { row.id, row }
    end) }
  end
end
```

This simple warmer will ensure that if you look for a row identifier in your cache, it's always going to be readily available (assuming it exists in the database). The format of the result value must be provided as either `{ :ok, pairs }` or `{ :ok, pairs, options }`. These pairs and options should match the same format you'd use when calling `Cachex.put_many/3`.

To make use of a warmer, a developer needs to assign it within the `:warmers` option during cache startup. This is where we can also control the frequency with which the warmer is run by setting the `:interval` option (which can also be `nil`):

```elixir
# for warmer()
import Cachex.Spec

# define the cache with our warmer
Cachex.start_link(:cache, [
  warmers: [
    warmer(
      state: connection,
      module: MyProject.DatabaseWarmer,
      interval: :timer.seconds(30),
      required: true
    )
  ]
])
```

The `:warmers` option accepts a list of `:warmer` records, which include information about the module, the warmer's state, and various other options. If your cache warmer is necessary for your application, you can flag it as `:required`. This will ensure that your cache supervision tree is not considered "started" until your warmer has run successfully at least once.

## Example Use Cases

To demonstrate this in an application, we'll use the same examples from the [Reactive Warming](reactive-warming.md) documentation, which is acting as a cache of an API call to retrieve a list of packages from a database. In the case of a cache miss, reactive warming would call the database and place the result in the cache for future calls.

With proactive warming, we can go a lot further. As creation of a package is infrequent, we can load the entire list into memory to guarantee we have everything accessible in our cache right from application startup:

```elixir
defmodule MyProject.PackageWarmer do
  @moduledoc """
  Module to warm the packages API.
  """
  use Cachex.Warmer

  @doc """
  Executes this cache warmer.
  """
  def execute(_) do
    # load all of the packages from the database
    packages = Repo.all(from p in Package)

    # create pairs from the API path and the package
    package_pairs = Enum.map(packages, fn(package) ->
      { "/api/v1/packages/#{package.id}", package }
    end)

    # return pairs for the root, as well as all single packages
    { :ok, [ { "/api/v1/packages", packages } | package_pairs ] }
  end
end
```

We then just provide our warmer during initialization of our cache, and define that it needs to be completed prior to startup via the `:required` flag. The `:interval` option is used to specify that it will refresh every 5 minutes:

```elixir
# need our records
import Cachex.Spec

# initialize our cache
Cachex.start_link(:cache, [
  warmers: [
    warmer(
      module: MyProject.PackageWarmer,
      interval: :timer.minutes(5),
      required: true
    )
  ]
])
```

As a result of being able to populate many keys at once we have not only populated `"/api/v1/packages"` to return the list of packages, but we have also populated the entire API `"/api/v1/packages/{id}"`. This is a much more optimized solution for this type of caching, as you can explode out your key writes with a single cache action, while requiring no extra database requests.

Somewhat obviously these warmers can only be used if you know what types of data you're expecting to be cached. If you're dealing with seeded data (i.e. from a user) you probably can't use proactive warming, and should be looking at reactive warming instead. You must also consider how relevant the data is that you're caching; if you only care about it for a short period of time, you likely don't want a warmer as they run for the lifetime of the cache.

## Triggered Warming

In addition to having your warmers managed by Cachex, it's now also possible to manually warm a cache. As of Cachex v4.x, the interface now includes `Cachex.warm/2` for this purpose. Calling this function will execute all warmers attached to a cache, or a subset of warmers you select at call time:

```elixir
# warm the cache manually
Cachex.warm(:my_cache)

# warm the cache manually and block until complete
Cachex.warm(:my_cache, wait: true)

# warm the cache manually, but only with specific warmers
Cachex.warm(:my_cache, only: [MyProject.PackageWarmer])
```

This is extremely helpful for things like evented cache invalidation and debugging. The Cachex internal management actually delegates through to this under the hood, meaning that there should be no surprising inconsistencies between managed vs. manual warming. It should be noted that `Cachex.warm/2` can be run either with or without an `:interval` set in your warmer record.
