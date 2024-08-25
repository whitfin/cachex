defmodule Cachex.Router.ModTest do
  use CachexCase

  test "routing keys via a modulo router" do
    # create a test cache cluster for nodes
    {cache, nodes} =
      Helper.create_cache_cluster(3,
        router: Cachex.Router.Mod
      )

    # convert the name to a cache and sort
    cache = Services.Overseer.retrieve(cache)
    nodes = Enum.sort(nodes)

    # fetch the router state after initialize
    cache(router: router(state: state)) = cache

    # test that we can route to expected nodes
    assert Services.Conductor.nodes(cache) == {:ok, nodes}
    assert Cachex.Router.Mod.route(state, "elixir") == Enum.at(nodes, 1)
    assert Cachex.Router.Mod.route(state, "erlang") == Enum.at(nodes, 0)
  end

  test "routing keys via a modulo router with defined nodes" do
    # create our nodes
    nodes = [:a, :b, :c]

    # create router from nodes
    router =
      router(
        module: Cachex.Router.Jump,
        options: [nodes: nodes]
      )

    # create a test cache and fetch back
    cache = Helper.create_cache(router: router)
    cache = Services.Overseer.retrieve(cache)

    # fetch the router state after initialize
    cache(router: router(state: state)) = cache

    # test that we can route to expected nodes
    assert Services.Conductor.nodes(cache) == {:ok, nodes}
    assert Cachex.Router.Mod.route(state, "elixir") == Enum.at(nodes, 1)
    assert Cachex.Router.Mod.route(state, "erlang") == Enum.at(nodes, 0)
  end
end
