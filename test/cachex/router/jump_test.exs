defmodule Cachex.Router.JumpTest do
  use CachexCase

  test "routing keys within a jump router" do
    # create a router from three node names
    router = Router.Jump.new([:a, :b, :c])

    # test that we can route to expected nodes
    assert Router.Jump.nodes(router) == [:a, :b, :c]
    assert Router.Jump.route(router, "elixir") == :b
    assert Router.Jump.route(router, "erlang") == :c
  end

  test "attaching a node causes an error" do
    assert_raise(RuntimeError, "Router does not support node addition", fn ->
      [node()]
      |> Router.Jump.new()
      |> Router.Jump.attach(node())
    end)
  end

  test "detaching a node causes an error" do
    assert_raise(RuntimeError, "Router does not support node removal", fn ->
      [node()]
      |> Router.Jump.new()
      |> Router.Jump.detach(node())
    end)
  end
end
