defmodule Cachex.Router.RingTest do
  use CachexCase

  test "routing keys via a ring router" do
    # create a test cache cluster for nodes
    {cache, _nodes} =
      Helper.create_cache_cluster(3,
        router:
          router(
            module: Cachex.Router.Ring,
            options: [
              nodes: [:a, :b, :c]
            ]
          )
      )

    # convert the name to a cache and sort
    cache = Services.Overseer.retrieve(cache)

    # fetch the router state after initialize
    cache(router: router(state: state)) = cache

    # test that we can route to expected nodes
    assert Services.Conductor.nodes(cache) == {:ok, [:c, :b, :a]}
    assert Cachex.Router.Ring.route(state, "elixir") == :c
    assert Cachex.Router.Ring.route(state, "erlang") == :b
  end

  test "routing keys via a ring router with monitored nodes" do
    # create a test cache cluster for nodes
    {cache, nodes} =
      Helper.create_cache_cluster(3,
        router:
          router(
            module: Cachex.Router.Ring,
            options: [
              monitor_nodes: true
            ]
          )
      )

    # convert the name to a cache and sort
    cache = Services.Overseer.retrieve(cache)
    nodes = Enum.reverse(nodes)

    # test that we can route to expected nodes
    assert Services.Conductor.nodes(cache) == {:ok, nodes}
  end
end
