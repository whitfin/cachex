# Local Persistence

Cachex ships with basic support for saving a cache to a local file using the [External Term Format](https://www.erlang.org/doc/apps/erts/erl_ext_dist). These files can then be used to seed data into a new instance of a cache to persist values between cache instances. As it stands all persistence must be handled manually via the Cachex API, although additional features may be added in future to add convenience around this.

## Writing to Disk

To save a cache to a file on disk, you can use the `Cachex.save/3` function. This function will handle compression automatically and populate the path on disk with a file you can import later. It should be noted that the internal format of this file should not be relied upon.

```elixir
:ok = Cachex.save(:my_cache, "/tmp/my_cache.dat")
```

The above demonstrates how simple it is to save your cache to a location on disk (in this case `/tmp/my_cache.dat`). Any options can be provided as a `Keyword` list as an optional third parameter.

## Loading from Disk

To seed a cache from an existing file, you can use `Cachex.restore/3`. This will *merge* the file into your cache, overwriting and clashing keys and maintaining any keys which existed in the cache beforehand. If you want a direct match of the file inside your cache, you should use `Cachex.clear/2` before loading your data.

```elixir
# optionally clean your cache first
amount = Cachex.clear(:my_cache)

# then you can load the existing save into your cache
^amount = Cachex.restore(:my_cache, "/tmp/my_cache.dat")
```

Please note that loading from an existing file will maintain all existing expirations, and records which have already expired will *not* be added to the cache table. This should not be surprising, but it is worth calling out.
