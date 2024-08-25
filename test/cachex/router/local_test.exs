defmodule Cachex.Router.LocalTest do
  use CachexCase

  test "routing keys via a local router" do
    # create a test cache
    cache = Helper.create_cache(router: Cachex.Router.Local)

    # convert the name to a cache and sort
    cache = Services.Overseer.retrieve(cache)

    # fetch the router state after initialize
    cache(router: router(state: state)) = cache

    # test that we can route to expected nodes
    assert Services.Conductor.nodes(cache) == {:ok, [node()]}
    assert Cachex.Router.Local.route(state, "elixir") == node()
    assert Cachex.Router.Local.route(state, "erlang") == node()
  end
end
