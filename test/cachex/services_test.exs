defmodule Cachex.ServicesTest do
  use Cachex.Test.Case

  test "generating application service definitions" do
    assert [
             %{id: Services.Overseer, start: {Services.Overseer, _, _}},
             %{id: Services.Locksmith, start: {Services.Locksmith, _, _}}
           ] = Services.app_spec()
  end

  test "generating default cache specifications" do
    # generate the test cache state
    name = TestUtils.create_cache()
    cache = Services.Overseer.lookup(name)

    # validate the services
    assert [
             %{id: Eternal, start: {Eternal, _, _}},
             %{
               id: Services.Locksmith.Queue,
               start: {Services.Locksmith.Queue, _, _}
             },
             %{id: Services.Informant, start: {Services.Informant, _, _}},
             %{id: Services.Incubator, start: {Services.Incubator, _, _}},
             %{id: Services.Courier, start: {Services.Courier, _, _}},
             %{id: Services.Janitor, start: {Services.Janitor, _, _}}
           ] = Services.cache_spec(cache)
  end

  test "generating cache specifications with routing" do
    # generate the test cache state using an async router
    name = TestUtils.create_cache(router: Cachex.Router.Ring)
    cache = Services.Overseer.lookup(name)

    # validate the services
    assert [
             %{id: Eternal, start: {Eternal, _, _}},
             %{id: ExHashRing.Ring, start: {ExHashRing.Ring, _, _}},
             %{
               id: Cachex.Router.Ring.Monitor,
               start: {GenServer, _, _}
             },
             %{
               id: Services.Locksmith.Queue,
               start: {Services.Locksmith.Queue, _, _}
             },
             %{id: Services.Informant, start: {Services.Informant, _, _}},
             %{id: Services.Incubator, start: {Services.Incubator, _, _}},
             %{id: Services.Courier, start: {Services.Courier, _, _}},
             %{id: Services.Janitor, start: {Services.Janitor, _, _}}
           ] = Services.cache_spec(cache)
  end

  test "skipping cache janitor specifications" do
    # generate the test cache state with the Janitor disabled
    name = TestUtils.create_cache(expiration: expiration(interval: nil))
    cache = Services.Overseer.lookup(name)

    # validate the services
    assert [
             %{id: Eternal, start: {Eternal, _, _}},
             %{
               id: Services.Locksmith.Queue,
               start: {Services.Locksmith.Queue, _, _}
             },
             %{id: Services.Informant, start: {Services.Informant, _, _}},
             %{id: Services.Incubator, start: {Services.Incubator, _, _}},
             %{id: Services.Courier, start: {Services.Courier, _, _}}
           ] = Services.cache_spec(cache)
  end

  test "locating running services" do
    # generate the test cache state with the Janitor disabled
    name = TestUtils.create_cache(expiration: expiration(interval: nil))
    cache = Services.Overseer.lookup(name)

    # validate the service locations
    assert Services.locate(cache, Services.Courier) != nil
    assert Services.locate(cache, Services.Janitor) == nil
  end
end
