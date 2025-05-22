# Distributed Caches

A distributed cache is a cache spanning multiple nodes which allows each individual node to store less data in memory, while maintaining the ability to access data stored on other nodes. This is all pretty transparent; in general you shouldn't have to think too much about it.

To demonstrate how this works, let's walk through a simple scenario:

* Let's say you have a cluster of 3 nodes
* You write 100 keys to a cache in your application
* You can expect e.g. ~30 keys stored on each node
* Writing a key on Node A may actually store the value on Node B
* Searching for that key on Node C will know to fetch it from Node B

The idea is that your cache is readily warm on each node in your cluster, even if the call to populate the key didn't occur on that node. If someone does an action when connected to Node A, it's placed in a hot layer accessible by both Node B and Node C even though no action was taken on either of those nodes.

It is important to be aware that the data is **not** replicated to every node; Cachex is a caching library, not a database. A cache provides an ephemeral data layer for an application; if you need data persistence across a cluster, you should another tool.

For further information on why Cachex should not be treated as a database, please see the additional context provided in [the related issue](https://github.com/whitfin/cachex/issues/246#issuecomment-2045591509).

## Cluster Routers

Distributed caches are controleld by the `Cachex.Router` implementation being used by a cache. The default router will only use the local node for key storage/retrieval, so we have to select a more appropriate router.

Cachex v4.x includes a new router based on Discord's [ex_hash_ring](https://github.com/discord/ex_hash_ring) library; this is a good router to get started with when using a distributed cache. It supports addition and removal of nodes based on OTP events, allowing for common use cases like Docker and Kubernetes.

To use this router at startup, provide the `:router` option when you call `Cachex.start_link/2`:

```elixir
# for records
import Cachex.Spec

# create a cache with a ring router
Cachex.start(:my_cache, [
  router: router(module: Cachex.Router.Ring)
])
```

If you wish to customize the behaviour of the router, you can see the supported options at `Cachex.Router.Ring.init/2`. These options can be provided in the same `router` record under the `:options` key.

For example to create a ring router which listens for addition/removal of nodes, we can set the `:monitor` option:

```elixir
# for records
import Cachex.Spec

# create a cache with a ring router
Cachex.start(:my_cache, [
  router: router(module: Cachex.Router.Ring, options: [
    monitor: true
  ])
])
```

This option will listen to `:nodeup` and `:nodedown` events and redistribute keys around your cluster automatically; you will generally always want this enabled if you're planning to dynamically add and remove nodes from your cluster.

You can also visit the [Cache Routers](./cache-routers.md) documentation for further information on this topic.

## Distribution Rules

There are a number of behavioural changes when a cache is in distributed state, and it's important to be aware of them. I realise this is a lot of information, but it's good to have it all documented.

Calling other nodes is very simple when it's just retrieving a key, but there are other actions which require more handling. As an example of this, Node A may have 3 keys while Node B may have 2 keys. In this instance, a `Cachex.size/2` call will return a count of `5` automatically by merging the results from both nodes. This is transparent for convenience, and applies to all cache actions. There are cases where you may with to run something like `Cachex.size/2` on a specific node, instead of the whole cluster. For this case, all cache actions also support the `:local` option which, when set to `true`, will return only the result from the local node.

In the case you're using an action which is based on multiple keys (such as `Cachex.put_many/3` or `Cachex.transaction/3`), all keys within a single call **must** live on the same destination node. This should not be surprising, and is similar to the likes of [Redis](https://redis.io) where this is also the case (at the time of writing). If you attempt to use these types of calls with keys which slot to different nodes, you will receive a `:cross_slot` error. As it's typically difficult to guarantee that your keys will slot to the same node, it's generally recommended to only call these functions with a single key when used in a distributed cache (and so `put_many/3` is then redundant).

There are a small number of actions which are simply unavailable when called in a distributed environment. An example of this is `Cachex.stream/3`, where there really is no logical approach to a sane implementation. These functions can not be run inside a distributed cache, although you can still opt into running them locally via `:local`.

## Referencing Functions

There are several actions within Cachex which accept a function as an argument. In these cases it's necessary to provide a reference to a function which is guaranteed to exist on all nodes in a cluster.

To expand on this, providing an inline function such as `fn x -> x * 2 end` will not work as expected, because it exists only on the local node. If this action is then delegated to a different node, the function no longer exists. Fortunately this is simple to work around, by instead naming the function within a module and providing it via `&MyModule.my_fun/1`.

This is mainly due to the naming conventions of anonymous functions, meaning that they cannot be guaranteed to be exactly the same on different OTP nodes. In the case of a named function, even though the anonymous binding is different, it's only passing through to a known function we can guarantee is consistent.

If this doesn't make sense, just remember to use module functions rather than inlined functions!

## Locally Available Actions

There are a few cache actions which will always execute locally, regardless of the state of the cache. This is due to either the semantics of their execution, or simply restrictions in their implementation. A good example of this is `Cachex.inspect/3`, which is used to debug the local cache. This wouldn't make sense in a distributed cache, so it doesn't even try.

Another pair of actions with this limitation are `Cachex.save/3` and `Cachex.restore/3`. Locally running these functions means that all filesystem interaction happens on the local node only, however these functions still provide save/restore functionality in a distributed cache due to how they're written internally.

When saving a cache to disk, `Cachex.save/3` makes use of `Cachex.export/2` which *is* available as a distributed action. When restoring a cache from disk, the `Cachex.restore/3` function uses `Cachex.put/4` internally, which is *also* available across nodes. This may be confusing at first, but after much consideration it was determined that this was the most sane design (even if it's quite odd).

It should also be noted that `Cachex.save/3` supports the `:local` option, and will pass it through to `Cachex.export/2`, making it possible to save only the data on the local node.
