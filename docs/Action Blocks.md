# Action Blocks

As of `v0.9.0`, support for action blocks has been incorporated into Cachex. These blocks provide different ways of executing a batch of actions sequentially inside a modified cache context. This change in context provides differences in behaviour which affect how your cache actions are carried out. Currently, they come in two flavours; execution blocks and transaction blocks. Each block uses a function provided with a `state` in order to utilise the scope correctly; if you don't pass the `state` to your cache calls and instead use the cache name, you'll lose out on the advantages of the block.

### Execution Blocks

An execution block is a pretty straightforward notion; due to Cachex requiring internal state to carry out a call, we can optimize this by retrieving the state once, executing all actions, then putting the state back. Back in the v1.x line, this was important as the state was stored in a GenServer and so an execution block would be a single GenServer call rather than N calls. Even though this is no longer backed by a GenServer there is still a throughput boost, so consider using these blocks if you're doing several cache calls in a row.

To provide an example, consider trying to retrieve two keys from a cache one after another. Below is an example both without and with an execution block:

```elixir
# without is the usual interface
val1 = Cachex.get!(:my_cache, "key1")
val2 = Cachex.get!(:my_cache, "key2")

# this is using an execution block
{ val1, val2 } = Cachex.execute!(:my_cache, fn(state) ->
  v1 = Cachex.get!(state, "key1")
  v2 = Cachex.get!(state, "key2")
  { v1, v2 }
end)
```

The syntax looks a little more complicated to start with, but you'll soon get used to it. It's a small trade off for a potentially large throughput boost (estimated best result would be 1/Nth of the time when N is the number of calls you're making).

It's very important to note that even though you're executing a block, other actions from other processes can happen at any time inside your block. To demonstrate this, here's a quick example:

```elixir
# start our execution block
Cachex.execute!(:my_cache, fn(state) ->
  # set a base value in the cache
  Cachex.set!(state, "key", "value")
  # we're paused but other stuff can happen
  :timer.sleep(5000)
  # this may have have been set elsewhere by this point
  Cachex.get!(state, "key")
end)
```

As we wait 5 seconds before reading the value back, the value may have been modified or even removed by other processes using the cache (such as TTL cleanup or other places in your application). If you want to guarantee that nothing is modified between your interactions, you should consider a transactional block instead.

### Transaction Blocks

One of the most useful blocks is the transactional block. These blocks will bind all actions inside into a transaction in order to ensure consistency, meaning that all actions defined in your transaction will execute sequentially with zero interaction from other processes. These blocks are quite similar in definition to execution blocks, except that they require a list of keys to lock throughout execution. Any keys not specified can still be written by other processes due to the optimizations made for locking.

```elixir
# start our execution block
Cachex.transaction!(:my_cache, [ "key" ], fn(state) ->
  # set a base value in the cache
  Cachex.set!(state, "key", "value")
  # we're paused but other stuff can not happen
  :timer.sleep(5000)
  # this will be guaranteed to return "value"
  Cachex.get!(state, "key")
end)
```

Naturally there is an overhead to transactions so use them only when you have to, however they're much more optimized than previous major versions of Cachex (as of `v2.x`) in that there should be no visible slowdown to writes against keys which do not have a lock. Transactional blocks are backed by a GenServer so be aware that throughput will line up with (at best) the throughput of GenServer calls.
