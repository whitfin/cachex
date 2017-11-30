defmodule Cachex.ServicesTest do
  use CachexCase

  test "generating application service definitions" do
    assert [
      { Services.Overseer, _, _, _, _, _ },
      { Services.Locksmith, _, _, _, _, _ }
    ] = Services.app_spec()
  end

  test "generating default cache specifications" do
    # generate the test cache state
    name  = Helper.create_cache()
    cache = Services.Overseer.retrieve(name)

    # validate the services
    assert [
      { Eternal, _, _, _, _, _ },
      { Services.Locksmith.Queue, _, _, _, _, _ },
      { Services.Informant, _, _, _, _, _ },
      { Services.Janitor, _, _, _, _, _ }
    ] = Services.cache_spec(cache)
  end

  test "generating cache limit specifications" do
    # generate the test cache state with a limit attached
    name  = Helper.create_cache([ limit: limit(size: 10, policy: __MODULE__.TestPolicy) ])
    cache = Services.Overseer.retrieve(name)

    # validate the services
    assert [
      { Eternal, _, _, _, _, _ },
      { Services.Locksmith.Queue, _, _, _, _, _ },
      { Services.Informant, _, _, _, _, _ },
      { Services.Janitor, _, _, _, _, _ },
      { Supervisor, { Supervisor, _, [ [ { __MODULE__.TestPolicy, _, _, _, _, _ } ], _ ] }, _, _, _, _ }
    ] = Services.cache_spec(cache)
  end

  test "skipping cache janitor specifications" do
    # generate the test cache state with the Janitor disabled
    name  = Helper.create_cache([ expiration: expiration(interval: nil) ])
    cache = Services.Overseer.retrieve(name)

    # validate the services
    assert [
      { Eternal, _, _, _, _, _ },
      { Services.Locksmith.Queue, _, _, _, _, _ },
      { Services.Informant, _, _, _, _, _ }
    ] = Services.cache_spec(cache)
  end

  defmodule TestPolicy do
    use Cachex.Policy

    import Supervisor.Spec

    def child_spec(_limit),
      do: [ worker(__MODULE__, [], []) ]

    def start_link,
      do: :ignore
  end
end
