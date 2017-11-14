defmodule Cachex.HookTest do
  use CachexCase

  # This test validates a list of hooks. If any hook in the list to be validated
  # are not valid, it short-circuits and returns an error. If all hooks are valid,
  # they're returned (in order). This test covers both of these cases. Right now
  # the only thing making a hook invalid is a bad module definition.
  test "validating a list of Hooks" do
    # create a valid Hook
    hook1 = ForwardHook.create()

    # create a hook with an invalid module
    hook2 = %Cachex.Hook{ hook1 | module: MissingModule }

    # validate the hooks individually
    result1 = Cachex.Hook.validate(hook1)
    result2 = Cachex.Hook.validate(hook2)

    # try validate both hooks
    result3 = Cachex.Hook.validate([ hook1, hook2 ])

    # the first hook should come back
    assert(result1 == { :ok, [ hook1 ] })

    # the second and third should error
    assert(result2 == { :error, :invalid_hook })
    assert(result3 == { :error, :invalid_hook })
  end
end
