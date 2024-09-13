# Local Persistence

Cachex ships with basic support for dumping a cache to a local file using the [External Term Format](https://www.erlang.org/doc/apps/erts/erl_ext_dist). These files can then be used to seed data into a new instance of a cache to persist values between cache instances.

As it stands all persistence must be handled manually via the Cachex API, although additional features may be added in future to add convenience around this. Note that the use of the term "dump" over "backup" is intentional, as these files are just extracted datasets from a cache, rather than a serialization of the cache itself.

## Writing to Disk

To dump a cache to a file on disk, you can use the `Cachex.dump/3` function. This function supports an optional `:compression` option (between `0-9`) to help reduce the required disk space. By default this value is set to `1` to try and optimize the tradeoff between performance and disk usage. Another common approach is to dump with `compression: 0` and run compression from outside of the Erlang VM.

```elixir
{ :ok, true } = Cachex.dump(:my_cache, "/tmp/my_cache.dump")
```

The above demonstrates how simple it is to dump your cache to a location on disk (in this case `/tmp/my_cache.dump`). Any options can be provided as a `Keyword` list as an optional third parameter.

## Loading from Disk

To seed a cache from an existing dump, you can use `Cachex.load/3`. This will *merge* the dump into your cache, overwriting and clashing keys and maintaining any keys which existed in the cache beforehand. If you want a direct match of the dump inside your cache, you should use `Cachex.clear/2` before loading your data.

```elixir
# optionally clean your cache first
{ :ok, _amt } = Cachex.clear(:my_cache)

# then you can load the existing dump into your cache
{ :ok, true } = Cachex.load(:my_cache, "/tmp/my_cache.dump")
```

Please note that loading from an existing dump will maintain all existing expirations, and records which have already expired will *not* be added to the cache table. This should not be surprising, but it is worth calling out.
