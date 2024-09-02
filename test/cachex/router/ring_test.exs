defmodule Cachex.Router.RingTest do
  use Cachex.Test.Case

  test "routing keys via a ring router" do
    # create a test cache cluster for nodes
    {cache, nodes, _cluster} =
      TestUtils.create_cache_cluster(3,
        router: Cachex.Router.Ring
      )

    # convert the name to a cache and sort
    cache = Services.Overseer.retrieve(cache)

    # fetch the router state after initialize
    cache(router: router(state: state)) = cache

    # test that we can route to expected nodes
    assert Services.Conductor.nodes(cache) == {:ok, nodes}
    assert Cachex.Router.Ring.route(state, "elixir") in nodes
    assert Cachex.Router.Ring.route(state, "erlang") in nodes
  end

  test "routing keys via a ring router with defined nodes" do
    # create a test cache cluster for nodes
    {cache, _nodes, _cluster} =
      TestUtils.create_cache_cluster(3,
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
    assert Services.Conductor.nodes(cache) == {:ok, [:a, :b, :c]}
    assert Cachex.Router.Ring.route(state, "elixir") == :b
    assert Cachex.Router.Ring.route(state, "erlang") == :c
  end

  @tag distributed: true
  test "routing keys via a ring router with monitored nodes" do
    # create a test cache cluster for nodes
    {cache, nodes, cluster} =
      TestUtils.create_cache_cluster(3,
        router:
          router(
            module: Cachex.Router.Ring,
            options: [
              monitor: true
            ]
          )
      )

    # convert the name to a cache and sort
    cache = Services.Overseer.retrieve(cache)

    # pull back the routable nodes from Conductor
    {:ok, routable1} = Services.Conductor.nodes(cache)

    # test that we can route to expected nodes
    assert length(nodes) == length(routable1)
    assert Enum.all?(nodes, &(&1 in routable1))

    # add two more members to the existing cache cluster
    {:ok, [member1, member2]} = LocalCluster.start(cluster, 2)

    # poll until async completion
    TestUtils.poll(250, true, fn ->
      {:ok, routable2} = Services.Conductor.nodes(cache)
      length(routable2) == 5
    end)

    # stop a single additional node
    LocalCluster.stop(cluster, member1)

    # poll until async completion
    TestUtils.poll(250, true, fn ->
      {:ok, routable3} = Services.Conductor.nodes(cache)
      length(routable3) == 4
    end)

    # stop the other remaining node
    LocalCluster.stop(cluster, member2)

    # poll until async completion
    TestUtils.poll(250, true, fn ->
      {:ok, routable3} = Services.Conductor.nodes(cache)
      length(routable3) == 3
    end)
  end
end
