defmodule Cachex.RouterTest do
  use CachexCase

  test "default Router implementations" do
    # create a router from three node names
    router = __MODULE__.DefaultRouter.new([:a, :b, :c])

    # check we can route and fetch the node list
    assert __MODULE__.DefaultRouter.nodes(router) == [:a, :b, :c]
    assert __MODULE__.DefaultRouter.route(router, "") == :a

    # verify that addition of a node is not applicable by default
    assert_raise(RuntimeError, "Router does not support node addition", fn ->
      __MODULE__.DefaultRouter.attach(router, node())
    end)

    # verify that removal of a node is not applicable by default
    assert_raise(RuntimeError, "Router does not support node removal", fn ->
      __MODULE__.DefaultRouter.detach(router, node())
    end)
  end

  defmodule DefaultRouter do
    use Cachex.Router

    def new(nodes, _opts \\ []),
      do: nodes

    def nodes(nodes),
      do: nodes

    def route(nodes, _key),
      do: Enum.at(nodes, 0)
  end
end
