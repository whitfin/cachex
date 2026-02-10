# Batching Actions

It's sometimes the case that you need to execute several cache actions in a row. Although you can do this in the normal, this is actually somewhat inefficient as each call has to do various management (such as looking up cache states). For this reason Cachex offers several mechanisms for making multiple calls in sequence.

## Submitting Batches

The simplest way to make several cache calls together is `Cachex.execute/3`. This API allows the caller to provide a function which will be provided with a pre-validated cache state which can be used (instead of the cache name) to execute cache actions. This will skip all of the cache management overhead you'd see typically:

```elixir
# standard way to execute several actions
r1 = Cachex.get(:my_cache, "key1")
r2 = Cachex.get(:my_cache, "key2")
r3 = Cachex.get(:my_cache, "key3")

# using Cachex.execute/3 to optimize the batch of calls
{r1, r2, r3} =
  Cachex.execute(:my_cache, fn cache ->
    # execute our batch of actions
    r1 = Cachex.get(cache, "key1")
    r2 = Cachex.get(cache, "key2")
    r3 = Cachex.get(cache, "key3")

    # pass back all results as a tuple
    {r1, r2, r3}
  end)
```

Although this syntax might look a little more complicated at a glance, it should be fairly straightforward to get used to. The small change in approach here gives a fairly large boost to cache throughput. To compare the two examples above, we can use a tool like [Benchee](https://github.com/PragTob/benchee) for a rough comparison:

```
Name                   ips        average  deviation         median         99th %
grouped             1.72 M      580.68 ns  ±3649.68%         500 ns         750 ns
individually        1.31 M      764.02 ns  ±2335.25%         625 ns         958 ns
```

We can clearly see the time saving when using the batched approach, even if there is a large deviation in the numbers above. Somewhat intuitively, the time saving scales to the number of actions you're executing in your batch, even if it is unlikely that anyone is doing more than a few calls at once.

It's important to note that even though you're executing a batch of actions, other processes can access and modify keys at any time during your `Cachex.execute/3` call. These calls still occur your calling process; they're not sent through any kind of arbitration process. To demonstrate this, here's a quick example:

```elixir
# start our execution block
Cachex.execute(:my_cache, fn cache ->
  # set a base value in the cache
  Cachex.put(cache, "key", "value")

  # we're paused but other changes can happen
  :timer.sleep(5000)

  # this may have have been set elsewhere
  Cachex.get(cache, "key")
end)
```

As we wait 5 seconds before reading the value back, the value may have been modified or even removed by other processes using the cache (such as TTL cleanup or other places in your application). If you want to guarantee that nothing is modified between your interactions, you should consider a transactional block instead.

## Transactional Batches

A transactional block will guarantee that your actions against a cache key will happen with zero interaction from other processes. Transactions look almost exactly the same as `Cachex.execute/3`, except that they require a list of keys to lock for the duration of their execution.

The entry point to a Cachex transaction is (unsurprisingly) `Cachex.transaction/4`. If we take the example from the previous section, let's look at how we can guarantee consistency between our cache calls:

```elixir
# start our execution block
Cachex.transaction(:my_cache, ["key"], fn cache ->
  # set a base value in the cache
  Cachex.put(cache, "key", "value")

  # we're paused but other changes will not happen
  :timer.sleep(5000)

  # this will be guaranteed to return "value"
  Cachex.get(cache, "key")
end)
```

It's critical to provide the keys you wish to lock when calling `Cachex.transaction/4`, as any keys not specified will still be available to be written by other processes during your function's execution. If you're making a simple cache call, the transactional flow will only be taken if there is a simultaneous transaction happening against the same key. This enables caches to stay lightweight whilst allowing for these batches when they really matter.

Another pattern which may prove useful is providing an empty list of keys, which will guarantee that your transaction runs at a time when no keys in the cache are currently locked. For example, the following code will guarantee that no keys are locked when purging expired records:

```elixir
Cachex.transaction(:my_cache, [], fn cache ->
  Cachex.purge(cache)
end)
```

Transactional flows are only enabled the first time you call `Cachex.transaction/4`, so you shouldn't see any peformance penalty in the case you're not actively using transactions. This also has the benefit of not requiring transaction support to be configured inside the cache options, as was the case in earlier versions of Cachex.

The last major difference between `Cachex.execute/3` and `Cachex.transaction/4` is where they run; transactions are executed inside a secondary worker process, so each transaction will run only after the previous has completed. As such there is a minor performance overhead when working with transactions, so use them only when you need to.
