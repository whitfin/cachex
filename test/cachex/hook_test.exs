defmodule Cachex.HookTest do
  use Cachex.Test.Case

  setup_all do
    ForwardHook.bind(
      concat_hook_1: [type: :pre],
      concat_hook_2: [type: :post],
      concat_hook_3: [type: :service]
    )

    :ok
  end

  test "concatenating hooks in a cache" do
    # create a set of 3 hooks to test with
    hook1 = ForwardHook.create(:concat_hook_1)
    hook2 = ForwardHook.create(:concat_hook_2)
    hook3 = ForwardHook.create(:concat_hook_3)

    # create a cache with our hooks
    cache =
      TestUtils.create_cache(
        hooks: [
          hook1,
          hook2,
          hook3
        ]
      )

    # turn the cache into a cache state
    cache1 = Services.Overseer.retrieve(cache)

    # compare the order and all hooks listed
    assert [
             {:hook, :concat_hook_3, _, _},
             {:hook, :concat_hook_2, _, _},
             {:hook, :concat_hook_1, _, _}
           ] = Cachex.Hook.concat(cache1)
  end

  test "locating hooks in a cache" do
    # create a set of 3 hooks to test with
    hook1 = ForwardHook.create(:concat_hook_1)
    hook2 = ForwardHook.create(:concat_hook_2)
    hook3 = ForwardHook.create(:concat_hook_3)

    # create a cache with our hooks
    cache =
      TestUtils.create_cache(
        hooks: [
          hook1,
          hook2,
          hook3
        ]
      )

    # turn the cache into a cache state
    cache1 = Services.Overseer.retrieve(cache)

    # locate each of the hooks (as they're different types)
    locate1 = Cachex.Hook.locate(cache1, :concat_hook_1)
    locate2 = Cachex.Hook.locate(cache1, :concat_hook_1, :pre)
    locate3 = Cachex.Hook.locate(cache1, :concat_hook_2, :post)
    locate4 = Cachex.Hook.locate(cache1, :concat_hook_3, :service)

    # verify they all come back just as expected
    assert {:hook, :concat_hook_1, _, _} = locate1
    assert {:hook, :concat_hook_1, _, _} = locate2
    assert {:hook, :concat_hook_2, _, _} = locate3
    assert {:hook, :concat_hook_3, _, _} = locate4

    # check that locating with the wrong type finds nothing
    assert Cachex.Hook.locate(cache1, :concat_hook_1, :post) == nil
  end
end
