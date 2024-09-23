# Cache Routers

New in Cachex v4.x, routing provides the developer the ability to determine how keys are assigned to nodes in a distributed caching cluster.

In previous versions of Cachex (namely v3.x) although there was support for routing within a cluster, the routing algorithm was neither configurable nor flexible. This lead to scenarios where it was simply insufficient, such as dynamically scaling caches. The new `Cachex.Router` module hopes to provide more flexibility to the developer, enabling them to choose the routing algorithm which best fits their use case.

## Default Routers

Cachex ships with several routers included, in an attempt to handle the most common use cases easily. The current set of included routers is as follows (at the time of writing):

| Module                | Description                                                                      |
|-----------------------|----------------------------------------------------------------------------------|
| `Cachex.Router.Local` | Routes keys to the local node only (the default)                                 |
| `Cachex.Router.Mod`   | Routes keys to a node using basic modulo hashing (i.e. `hash(key) % len(nodes)`) |
| `Cachex.Router.Jump`  | Routes keys to a node using the Jump Consistent hash algorithm                   |
| `Cachex.Router.Ring`  | Routes keys to a node using Discord's hash ring implementation                   |

Each of these routers has different strengths and weaknesses, so it's up to you to choose which best fits your use case. As a rule of thumb:

* If you are using a single node, use `Cachex.Router.Local`
* If you are using a statically sized cluster, use `Cachex.Router.Mod` or `Cachex.Router.Jump`
* If you are using a dynamically sized cluster, use `Cachex.Router.Ring`
* If you want the same behaviour as Cachex v3.x, use `Cachex.Router.Jump`

Once you know which router you want, you can configure it in your cache's options.

## Selecting a Router

To select a router for your cache, you should provide the `:router` option when starting your cache:

```elixir
# for records
import Cachex.Spec

# create a cache with a router
Cachex.start(:my_cache, [
  router: router(module: Cachex.Router.Local)
])
```

You can also provide options to pass to the router during initialization, in the case your router supports different configurations:

```elixir
# for records
import Cachex.Spec

# create a cache with a router
Cachex.start(:my_cache, [
  router: router(
    module: Cachex.Router.Jump,
    options: [
      nodes: [self()]
    ]
  )
])
```

Please see the module documentation for each router for further information, including options which may be used to customize the behaviour of the router.

## Implementing Routers

Although Cachex's included routers should be sufficient for many cases, they likely won't be enough for every case. For this reason it's possible for a developer to write their own router to have more control over a cache.

A router is defined by the behaviour `Cachex.Router`. Implementing this behaviour in your own router will allow you to provide it as a module to the `:router` option at cache startup, and Cachex will automatically plug into it when routing keys in a cluster. The behaviour looks something like this:

```elixir
@doc """
Initialize a routing state for a cache.
"""
@callback init(cache :: Cachex.t(), options :: Keyword.t()) :: any

@doc """
Retrieve the list of nodes from a routing state.
"""
@callback nodes(state :: any) :: [atom]

@doc """
Route a key to a node in a routing state.
"""
@callback route(state :: any, key :: any) :: atom

@doc """
Create a child specification to back a routing state.
"""
@callback children(cache :: Cachex.t(), options :: Keyword.t()) ::  Supervisor.child_spec()
```

As a demonstration let's walk through implementing a router using the logic that [Redis](https://redis.io/docs/latest/operate/oss_and_stack/management/scaling/) follows.

At the time of writing Redis will generate a CRC16 for a key, and then route it to one of 16384 hash slots distributed around a cluster. Hash slots are assigned in groups, so a 3 node cluster would look like this:

* Node A contains hash slots from 0 to 5500.
* Node B contains hash slots from 5501 to 11000.
* Node C contains hash slots from 11001 to 16383.

Using this information, we can create a `Cachex.Router` implementation to do something similar. We'll use the [crc](https://hexdocs.pm/crc) package to generate our CRC16 values:

```elixir
defmodule MyCustomRouter do
  @moduledoc """
  A very simple demonstration router based on Redis.
  """
  use Cachex.Router

  # our available slots
  @max_slots 16384

  @doc """
  Initialize the router state.

  This will return a list of connected nodes in our cluster.
  """
  def init(_cache, _options),
    do: [node() | :erlang.nodes(:connected)]

  @doc """
  Retrieve the nodes in our router state.

  As our state is just a list of nodes, this is returned as-is.
  """
  def nodes(nodes),
    do: nodes

  @doc """
  Routes a key to a node in the router state.

  This will implement our main logic, returning the name of a
  node that the provided key should be routed over to.
  """
  def route(nodes, key) do
    # generate our CRC16 value
    crc_for_key = CRC.crc_16(key)

    # calculate the number of slots per node
    slots_per_node = trunc(16384 / length(nodes))

    # create groups of slots to compare with
    slots_for_nodes =
      0..(@max_slots - 1)
      |> Enum.chunk_every(slots_per_node)
      |> Enum.with_index()

    # convert our CRC16 to a slot in the cluster
    slot_for_key = rem(crc_for_key, @max_slots)

    # locate the group which contains our slot
    {_group, idx} =
      Enum.find(slots_for_nodes, fn {slots, _idx} ->
        Enum.member?(slots, slot_for_key)
      end)

    # return the node name
    Enum.at(nodes, idx)
  end
end
```

This is obviously a very naive implementation for demonstration purposes; it could definitely be improved. That being said, hopefully this shows how easy it is to create our own router for our own requirements.

You may have noticed that we didn't need to implement `children/2`; this is because we can determine our key routing without need of any child processes. More complicated routers are able to spawn child processes under the main cache supervision tree in order to handle more complicated operations which require extra state management.

With our completed router, we can now create a cache and pass it in at startup:

```elixir
# for records
import Cachex.Spec

# create a cache with our router
Cachex.start(:my_cache, [
  router: router(module: MyCustomRouter)
])
```

Routing will now be managed by our custom routing logic, instead of the default Cachex router; we no longer have to rely on routing implementations to be included alongside Cachex!
