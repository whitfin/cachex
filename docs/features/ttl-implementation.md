# TTL Implementation

Cachex implements several different ways of working with key expirations, each operating in different ways with different behaviour. The two main techniques being currently used are the background TTL loop (i.e. the `Janitor`) and lazy key expiration. Alone these two techniques aren't sufficient to provide an efficient system with a consistent result, but together they ensure the reliability of your cache as well as ensuring correctness. Having said this it should be noted that there are cases where you may wish to use only one, as each technique is sufficient alone in specific scenarios. By default Cachex opts for a combination of both in order to ensure consistency to reduce surprises for the user.

## Janitor Processes

The Janitor is a background process which will purge the internal tables every so often. The Janitor operates using a full-table sweep of the records to ensure nothing is missed, and so it runs somewhat less frequently - by default only every few seconds. This interval can be controlled by the user, and a Janitor process exists on a per-cache basis (so that each cache doesn't have an interleaved dependency).

As it stands the Janitor is pretty well optimized as most expense is handed over to the ETS layer; it can currently check and purge 500,000 expired keys in around a second (where the removal takes the most time, the check is very fast). Keep in mind that the frequency of the Janitor execution affects the memory usage held by expired keys; a typical use case is probably running the Janitor every few seconds, which is pretty much the default. In a production application I know of using Cachex, Janitors have been running every 3 seconds for the last year and there has never been any noticeable slowdown.

As of Cachex v3, the Janitor configuration is easier to understand, and will be enabled by default to avoid catching users off guard:

- By default, the Janitor will run every 3 seconds.
- If you set `:interval` to `nil` it is disabled entirely. This means you will be solely reliant on the lazy expiration policy.
- If you set `:interval` to any numeric value above `0` it will run on this schedule (this value is in milliseconds!!).

Please note that this is rolling interval that is set to trigger after completion of a run, meaning that if you schedule a Janitor every 5s it will be 5s after a successful run rather than 5s after the last trigger fired to start a run.

## Lazy Expiration

A record contains an internal touch time and TTL associated with them, and these values do not change unless explicitly triggered by a Cachex call. This means that we have access to these values when we pull back a key, allowing us to very easily check for key expiry on retrieval before returning it to the user. If we check this at retrieval time and the record is expired, we would actually fire off a deletion at that time before returning `nil` to the user.

The advantage here is that if your Janitor hasn't run recently or is disabled completely, you can still never retrieve an expired key. This in turn allows the Janitor to run less frequently as you don't have to be as worried about stale values potentially coming back in cache calls. Naturally this technique cannot stand on it's own legs as it only evicts on key retrieval. If you never touch a record again, it would never be expired and thus your cache would just keep growing. It is for this reason that the Janitor is enabled by default when a TTL is set to protect the user from memory errors in their application.

There are certain situations when you don't care about the consistency of expirations, only that they expire at some point. For this reason you can disable lazy expiration as of `v0.10.0` in order to remove the (extremely minimal) overhead of checking expirations on read which can be valuable in a cache where reads are of extremely high volume. To disable you can set the `:lazy` option to be `false` at cache start. Another big advantage of disabling lazy expiration is that the execution time of any given read operation is more predictable due to avoiding the case where some reads may also need to evict a key.

## Setting Key Expirations

Default expiration times are defined in `Cachex.start_link/2`. See the details for the `:expiration` option. They canbe overridden on a case by case basis as follows:

- Specifying a `:ttl` option in `Cachex.put/4` or `Cachex.put_many/3`. These are special cases due to their heavy use.
- Calling `Cachex.expire/4` (or the closely related `Cachex.expire_at/4`) for a key that already exists.
