# Proactive Warming

## Overview

Introduced alongside Cachex v3, cache warmers act as an eager fallback. Rather than waiting for a cache miss to retrieve a value, values will be pulled up front to ensure that there is never a miss. This can be viewed as being proactive, whereas a fallback is reactive. As such, this is a better use case for those who know what data will be requested, rather than those dealing with arbitrary data.

Warmers are deliberately easy to create, as anything complicated belongs outside of Cachex itself. A warmer is simply a module which implements the `Cachex.Warmer` behaviour, which consists of just two callbacks at the time of writing (please see the `Cachex.Warmer` documentation to verify). The two callbacks are simply `interval/0` which returns a millisecond integer defining how often the warmer should execute, and `execute/1` which actually implements the cache warming. The easiest way to explain a warmer is to implement one, so let's do so; we'll implement a warmer which reads from a database via the module `DatabaseWarmer`.

## Definition

First of all, let's define our warmer on a cache at startup:

```elixir
# for warmer()
import Cachex.Spec

# define the cache with our warmer
Cachex.start_link(:my_cache, [
  warmers: [
    warmer(
      module: MyProject.DatabaseWarmer,
      state: connection
    )
  ]
])
```

These are generally the only two fields you'll have to set in a `warmer()~ record; a `:module` tag to define the module, and a `:state` field to define the state to be provided to the warmer (used later). The state in this case is a connection handle to our database, since we'll need that for queries we're trying to warm.

In terms of other useful options, you may pass a `:name` to use as the warmer's process name, which will default to the PID used by the process. You can also use the `:required` flag to signal whether it is necessary for a warmer to fully execute before your cache is deemed available. This defaults to `true`, but can easily be set to `false` if you're happy for your data to load asynchronously.

With our cache created, all that remains is to implement our `DatabaseWarmer` module which implements the warmer behaviour:

```elixir
defmodule MyProject.DatabaseWarmer do
  @moduledoc """
  Dummy warmer which caches database rows every 30s.
  """
  use Cachex.Warmer

  @doc """
  Returns the interval for this warmer.
  """
  def interval,
    do: :timer.seconds(30)

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

There are a couple of things going on here; first of all the `interval/0` is stating that we should execute every 30s (including on cache startup). Every 30 seconds, the `execute/1` callback is fired using the connection we passed at cache startup. We query the database to get all of the matching rows back, and then handle the response. In the case of an error (or really, any situation you don't want to write the results), we return `:ignore` which signals that the warmer was basically a no-op. In a successful execution, we need to map the results to one of two forms: `{ :ok, pairs }` or `{ :ok, pairs, options }`. The pairs/options act as the same format one would pass to `Cachex.put_many/3`, so check out those docs if you need to. These pairs are basically `{ key, value }`, so in our case we're caching row identifiers -> rows in our cache. Not particularly useful, but it'll do for now.

This demonstrates that a single warmer can warm a whole bunch of records in a single pass; this is especially useful when fetching remote data, as otherwise you'd need a warmer for every piece coming back from a request. This would be sufficiently complicated that you'd likely just roll your own warming instead, and so Cachex tries to negate this aspect by the addition of `put_many/3` in v3.x.

## Use Cases

To demonstrate this, we'll use the same examples from the fallback documentation, which is acting as a cache of an API call to `/api/v1/packages` which returns a list of packages. In case of a cache miss, a fallback will fetch that API and put it in the cache for future calls. With a warmer we can actually go a lot further for this use case:

```elixir
# need our records
import Cachex.Spec

# initialize our cache with a database connection
Cachex.start_link(:my_cache, [
  warmers: [
    warmer(module: MyProject.PackageWarmer, state: connection)
  ]
])
```

And then we define our warmer to do the same thing; pull the packages from the database every 5 minutes. It should be noted that a fallback runs **at most** every 5 minutes, whereas a warmer will run **always** every 5 minutes.

```elixir
defmodule MyProject.PackageWarmer do
  @moduledoc """
  Module to warm the packages API.
  """
  use Cachex.Warmer

  @doc """
  Returns the interval for this warmer.
  """
  def interval,
    do: :timer.minutes(5)

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

Using the same amount of database calls, on the same frequency, we have not only populated `"/api/v1/packages"` to return the list of packages, but we have also populated the entire API `"/api/v1/packages/{id}"` to return the single package referenced in the path. This is a much more optimized solution for this type of caching, as you can explode out your key writes with a single cache action, and no extra database requests.

Obviously, these warmers can only be used if you know what types of data you're expecting to be cached. If you're dealing with seeded data (i.e. from a user), you probably can't use warmers, and should be looking at fallbacks instead. You must also consider how relevant the data is that you're caching; if you only care about it for a short period of time, you likely don't want a warmer as they run for the lifetime of the cache.
