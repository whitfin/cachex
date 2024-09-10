# Proactive Warming

## Overview

Introduced alongside Cachex v3, cache warmers act as an eager fallback. Rather than waiting for a cache miss to retrieve a value, values will be pulled up front to ensure that there is never a miss. This can be viewed as being proactive, whereas `Cachex.fetch/4` is reactive. As such, this is a better use case for those who know what data will be requested, rather than those dealing with arbitrary data.

Warmers are deliberately easy to create, as anything complicated belongs outside of Cachex itself. A warmer is simply a module which implements the `Cachex.Warmer` behaviour, which consists of just a single callbacks at the time of writing (please see the `Cachex.Warmer` documentation to verify). A warmer should expose `execute/1` which actually implements the cache warming. The easiest way to explain a warmer is to implement one, so let's do so; we'll implement a warmer which reads from a database via the module `DatabaseWarmer`.

## Definition

First of all, let's define our warmer on a cache at startup:

```elixir
# for warmer()
import Cachex.Spec

# define the cache with our warmer
Cachex.start_link(:my_cache, [
  warmers: [
    warmer(
      interval: :timer.seconds(30),
      module: MyProject.DatabaseWarmer,
      state: connection
    )
  ]
])
```

The fields above are generally the only three fields you'll have to set in a `warmer()` record. The `:module` tag defines the module implementing the `Cachex.Warmer` behaviour, the `:state` field defines the state to be provided to the warmer (used later), and the `:interval` controls the frequency with which the warmer executes (in milliseconds). In previous versions of Cachex the `:interval` option was part of the module behaviour, but this was changed to be more flexible.

In terms of some of the other options, you may pass a `:name` to use as the warmer's process name (which defaults to the PID being used by the process). You can also use the `:required` flag to signal whether it is necessary for a warmer to fully execute before your cache is deemed "available". This defaults to `true` but can easily be set to `false` if you're happy for your data to load asynchronously. The `:required` flag in Cachex v4.x is the same as `async: false` in Cachex v3.x.

With our cache created all that remains is to create our `DatabaseWarmer` module, which implements our warmer behaviour:

```elixir
defmodule MyProject.DatabaseWarmer do
  @moduledoc """
  Dummy warmer which caches database rows every 30s.
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

There are a couple of things going on here;

* When our `execute/1` callback is fired, we query the database and map all rows into the warmer response format.
  * In case of error (or any situation you don't want to write the results), we return `:ignore` to signal the warmer should be a no-op
  * In case of success, we need to map the results to one of two forms: `{ :ok, pairs }` or `{ :ok, pairs, options }`
* The returned tuples from the warmer are placed into the cache table

When formatting results to place into the cache table, both the pairs and options should be provided in the same format that you'd use when calling `Cachex.put_many/3`, so check out the documentation if you need to. In our example above these pairs are simply storing `row.id -> row` in our cache. Not particularly useful, but it'll do for now!

Although simple, this example demonstrates that a single warmer can populate many records in a single pass. This is particularly useful when fetching remote data, instead of using a warmer for every row in a database. This would be sufficiently complicated that you'd likely just roll your own warming instead, and so Cachex tries to negate this aspect by the addition of `put_many/3` in v3.x.

## Use Cases

To demonstrate this, we'll use the same examples from the [Reactive Warming](reactive-warming.md) documentation, which is acting as a cache of an API call to `/api/v1/packages` which returns a list of packages. In case of a cache miss, reactive warming will call the API and put it in the cache for future calls. With a warmer we can actually go a lot further for this use case:

```elixir
# need our records
import Cachex.Spec

# initialize our cache with a database connection
Cachex.start_link(:my_cache, [
  warmers: [
    warmer(
      interval: :timer.minutes(5),
      module: MyProject.PackageWarmer,
      state: connection
    )
  ]
])
```

And then we define our warmer to do the same thing; pull the packages from the database every 5 minutes. It should be noted that reactive warming runs **at most** every 5 minutes, whereas a proactive warmer will **always** run every 5 minutes with a provided interval.

```elixir
defmodule MyProject.PackageWarmer do
  @moduledoc """
  Module to warm the packages API.
  """
  use Cachex.Warmer

  @doc """
  Executes this cache warmer with a connection.
  """
  def execute(connection) do
    # load all of the packages from the database
    packages = Database.load_packages(db_conn)

    # create pairs from the API path and the package
    package_pairs = Enum.map(packages, fn(package) ->
      { "/api/v1/packages/#{package.id}", package }
    end)

    # return pairs for the root, as well as all single packages
    { :ok, [ { "/api/v1/packages", packages } | package_pairs ] }
  end
end
```

Using the same amount of database calls, on the same frequency, we have not only populated `"/api/v1/packages"` to return the list of packages, but we have also populated the entire API `"/api/v1/packages/{id}"` to return the single package referenced in the path. This is a much more optimized solution for this type of caching, as you can explode out your key writes with a single cache action, while requiring no extra database requests.

Somewhat obviously these warmers can only be used if you know what types of data you're expecting to be cached. If you're dealing with seeded data (i.e. from a user) you probably can't use warmers, and should be looking at reactive warming instead. You must also consider how relevant the data is that you're caching; if you only care about it for a short period of time, you likely don't want a warmer as they run for the lifetime of the cache.

# Infrequent Warming

In some cases you may not wish to use automated interval warming, such as if your data is static and changes rarely or doesn't change at all. For this case Cachex v4.x allows the `:interval` to be `nil`, which will only run your warmer a single time on cache startup. It also introduces `Cachex.warm/2` to allow the developer to manually warm a cache and implement their own warming schedules.

When using manual warming, your cache definition is much the same as before:

```elixir
# need our records
import Cachex.Spec

# initialize our cache with a database connection
Cachex.start_link(:my_cache, [
  warmers: [
    warmer(
      module: MyProject.PackageWarmer,
      state: connection
    )
  ]
])
```

Cachex will run this warmer a single time on cache startup, and then never again (due to the developer not providing the `:interval` options). In this case the developer will have to manually fire the warmer via `Cachex.warm/2`:

```elixir
# warm the cache manually
Cachex.warm(:my_cache)

# warm the cache manually and block until complete
Cachex.warm(:my_cache, wait: true)

# warm the cache manually, but only with specific warmers
Cachex.warm(:my_cache, only: [MyProject.PackageWarmer])
```

To extend the previous example to benefit from this type of warming, imagine that there is a separate API to create a new package. In this case you could manually warm your cache after a package is created, rather than re-warm every 5 minutes if nothing has changed in the meantime.

It's also worth noting that manual warming is still available even if you *have* specified the `:interval` option, so if you have a high cache interval of something like `:timer.hours(24)` and you want to trigger an earlier warming, you can always `iex` into your node and run a cache warming manually.
