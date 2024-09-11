# Distributed Caches

First introduced in the `v3.1.0` release, Cachex provides the ability to spread your caches across the nodes of an Erlang cluster. Doing this provides an easy way to share data across a cluster; for example if a cache entry is written on Node A, it's possible to retrieve it on Node B. This is accomplished via a simple table sharding algorithm which splits your cache data across nodes in the cluster based on the provided key.

## Overview

Cachex intends to provide a very straightforward interface for dealing with a distributed setup; it's intended to be almost invisible to the caller as to whether their keys are coming from the local node or a remote node. When creating your cache, you simple provide a `:nodes` option which contains a list of all nodes that will run the cache. Each node provided much also be configured to run a `Cachex` instance (with the same options). If any of the nodes are unreachable, your cache will not be started and an error will be returned. To aid in the case of development, Cachex will attempt a basic `Node.connect/1` call to try to communicate with each node. In the interest of fault tolerance, you should likely use other methods of node management to handle things like partitions and reconnection as needed.

There are few rules in place for the communication with remote nodes. Any key based actions are routed to the appropriate node (whether local or remote), and any cache based actions are aggregated using the results from each individual node. As an example of this, consider that Node A may have 3 keys and Node B may have 2 keys. In this scenario, a `size/2` call will return a count of `5` automatically. If you desire to only retrieve the result from the local node, these cache based actions all support a `:local` option which, when set to `true`, will return only the result from the local node.

In the case you're using an action based on multiple keys (such as `put_many/3` or `transaction/3`), all targeted keys must live on the same target node. This is similar to the likes of [Redis](https://redis.io) where this is also the case. If you try to use either of these functions with keys which slot to different nodes, you will receive a `:cross_slot` error. As it's typically difficult to guarantee that your keys will slot to the same node, it's generally recommended to only call these functions with a single key when used in a distributed cache (and so `put_many/3` is then redundant).

## Local Actions

There are a few actions which will always execute locally, due to either the semantics of their execution, or restrictions on their implementation. One such example is the `inspect/3` function, which will always run on the local node. This is due to it being mainly used for debugging purposes, as it provides what is currently one of the only ways to interact with the local table when it would otherwise be routed to another node. As the inspector is more useful for development, this isn't really much of a limitation.

Also running locally are the functions `dump/3` and `load/3`, however this might be slightly confusing at first. Running locally for these functions essentially means that all filesystem interaction happens on the local node only. However these functions still provided backup/restore functionality for a distributed cache due to how they function internally through the use of delegates. In order to serialize a cache to disk, the `dump/3` action makes use of the `export/2` action (introduced in `v3.1.0` for this reason), which *is* available across multiple nodes. Likewise, the `load/3` function uses `put/4` internally to re-import a serialized cache, which is also available across nodes. It should also be noted that because `dump/3` is a cache based action, it does also support the `:local` option.

As it stands, this is a full list of local-only functions. If more are added in future, they will be listed in this documentation.

## Disabled Actions

Due to complications with their implementation, there are a small number of actions which are currently unavailable when used in a distributed environment. They're defined below, along with reasonings as to why. It should be noted that just because certain actions are disabled currently, does not mean that they will always be disabled (although there is no guaranteed they will ever be enabled).

One action that is likely to never be made compatible is the `stream/3` action. This is for a couple of reasons; the first being that streaming a cache across nodes doesn't really make too much sense. It would be very complex to keep track of multiple cursors on each node in order to "stream" the cache on a single node. What's more, because a `Stream` in Elixir is essentially an anonymous function, it's not trivial to even implement a stream - each call to the stream would have to RPC (one by one) to each remote node to fetch the next value. This is of course rather expensive, and so it's recommended to simply construct a list to avoid the need to stream.

As it stands, this is a full list of disabled functions. If more are added in future, they will be listed in this documentation.

## Passing Functions

There are a few actions in Cachex which require a function as an argument. In these scenarios you should ensure to provide a reference to a function guaranteed to exist on each node. As an example, providing an inline `fn(x) -> x * 2 end` is insufficient. You should instead name the function and provide it via `&MyModule.my_fun/1`. This is due to the naming conventions of anonymous functions and they can't be guaranteed to be the same on different nodes. Named function references are fine, because even though the anonymous binding is different, it's only passing through to a named function we can guarantee is the same.
