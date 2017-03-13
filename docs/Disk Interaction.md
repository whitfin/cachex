# Disk Interaction

As of `v2.1.0` Cachex ships with support for dumping a cache to a local file using the Erlang Term Format. These raw files can then be used to seed data into a new instance of a cache to persist values between cache instances. As it stands currently this must be done manually via the Cachex interface, although there may be features added in future to backup automatically on a provided interval. Note that the use of the term "dump" over "backup" is intentional, as these dumps are just extracted datasets from a cache, rather than a serialization of the cache itself.

To dump a cache to disk you can use the `dump/3` function, which accepts an optional compression option (between `0-9`) to save on disk space. The default compression level is set to `1` as it optimizes the tradeoff between performance and disk space, but if you wish to compress more thoroughly it's typically recommended that you write with `0` compression and then compress from outside of the VM to avoid a potentially longer execution time impacting your application.

To use a dump to seed a new cache, you can use the `load/2` function. Please note that this will merge a dumped dataset into the cache, overwriting any clashing keys. If you want to match the dump exactly you should clear the cache before loading your data. This function does not need a compression option specifying as it's stored in the compressed file itself during the dump. The following demonstrates how to go about dumping a cache and then loading it back from the dumped file:

```elixir
# set some values in a cache
:ok = Enum.each(1..5, fn(x) ->
  { :ok, true } = Cachex.set(:my_cache, x, x)
end)

# verify the size of the cache == 5
{ :ok, 5 } = Cachex.size(:my_cache)

# write our cache to disk
{ :ok, true } = Cachex.dump(:my_cache, "/tmp/my_backup")

# clear our local cache
{ :ok, 5 } = Cachex.clear(:my_cache)

# now the size will equal zero
{ :ok, 0 } = Cachex.size(:my_cache)

# reload the cache from the disk
{ :ok, true } = Cachex.load(:my_cache, "/tmp/my_backup")

# now the values will exist again
{ :ok, 5 } = Cachex.size(:my_cache)
```

Cache dumps are written using ETF rather than `:ets` based persistence for both performance and to reduce the coupling with `:ets` in case we ever need to move away from it. A cache dump can be transferred between machines and most (if not all) Erlang versions currently compatible with Elixir. You must have started your cache before loading a dump otherwise the table won't be bootstrapped correctly.
