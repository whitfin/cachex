defmodule Cachex.Services.StewardTest do
  use Cachex.Test.Case

  test "provisioning cache state" do
    # bind our hook
    ForwardHook.bind(
      steward_forward_hook_provisions: [
        provisions: [:cache]
      ]
    )

    # create our hook with the provisions forwarded through to it
    hook = ForwardHook.create(:steward_forward_hook_provisions)

    # start a new cache using our forwarded hook
    cache = TestUtils.create_cache(hooks: [hook])
    cache = Services.Overseer.lookup(cache)

    # the provisioned value should match
    assert_receive({:cache, ^cache})
  end
end
