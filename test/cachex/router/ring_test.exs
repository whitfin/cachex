defmodule Cachex.Router.RingTest do
  use CachexCase

  test "routing keys within a ring router" do
    # create a router from three node names
    router = Router.Ring.new([:a, :b, :c])

    # test that we can route to expected nodes
    assert Router.Ring.nodes(router) == [:a, :b, :c]
    assert Router.Ring.route(router, "elixir") == :c
    assert Router.Ring.route(router, "erlang") == :b
  end

  test "attaching and detaching node in a ring router" do
    # create a router from three node names
    router = Router.Ring.new([:a, :b, :c])

    # verify the routing of various keys
    assert Router.Ring.nodes(router) == [:a, :b, :c]
    assert Router.Ring.route(router, "elixir") == :c
    assert Router.Ring.route(router, "erlang") == :b
    assert Router.Ring.route(router, "fsharp") == :c

    # attach a new node :d to the router
    router = Router.Ring.attach(router, :d)

    # route the same keys again, fsharp is resharded
    assert Router.Ring.nodes(router) == [:a, :b, :c, :d]
    assert Router.Ring.route(router, "elixir") == :c
    assert Router.Ring.route(router, "erlang") == :b
    assert Router.Ring.route(router, "fsharp") == :d

    # remove the node :d from the router
    router = Router.Ring.detach(router, :d)

    # the key fsharp is routed back to the initial
    assert Router.Ring.nodes(router) == [:a, :b, :c]
    assert Router.Ring.route(router, "elixir") == :c
    assert Router.Ring.route(router, "erlang") == :b
    assert Router.Ring.route(router, "fsharp") == :c
  end
end
