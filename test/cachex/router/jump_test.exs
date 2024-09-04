defmodule Cachex.Router.JumpTest do
  use Cachex.Test.Case

  test "routing keys via a jump router" do
    # create a test cache cluster for nodes
    {cache, nodes, _cluster} =
      TestUtils.create_cache_cluster(3,
        router: Cachex.Router.Jump
      )

    # convert the name to a cache and sort
    cache = Services.Overseer.retrieve(cache)
    nodes = Enum.sort(nodes)

    # fetch the router state after initialize
    cache(router: router(state: state)) = cache

    # test that we can route to expected nodes
    assert Cachex.Router.nodes(cache) == {:ok, nodes}
    assert Cachex.Router.Jump.route(state, "elixir") == Enum.at(nodes, 1)
    assert Cachex.Router.Jump.route(state, "erlang") == Enum.at(nodes, 2)
  end

  test "routing keys via a jump router with defined nodes" do
    # create our nodes
    nodes = [:a, :b, :c]

    # create router from nodes
    router =
      router(
        module: Cachex.Router.Jump,
        options: [nodes: nodes]
      )

    # create a test cache and fetch back
    cache = TestUtils.create_cache(router: router)
    cache = Services.Overseer.retrieve(cache)

    # fetch the router state after initialize
    cache(router: router(state: state)) = cache

    # test that we can route to expected nodes
    assert Cachex.Router.nodes(cache) == {:ok, nodes}
    assert Cachex.Router.Jump.route(state, "elixir") == Enum.at(nodes, 1)
    assert Cachex.Router.Jump.route(state, "erlang") == Enum.at(nodes, 2)
  end
end
