defmodule Cachex.HookTest do
  use CachexCase

  # This test ensures that we are able to broadcast a set of results from an out
  # of bound process to all post_hooks (and only post_hooks).
  test "broadcasting results to a list of hooks" do
    # create a pre and post hook
    hook1 = ForwardHook.create(%{ type:  :pre })
    hook2 = ForwardHook.create(%{ type: :post })

    # start a cache with the hooks
    cache1 = Helper.create_cache([ hooks: [ hook1 ] ])
    cache2 = Helper.create_cache([ hooks: [ hook2 ] ])

    # broadcast using the cache name
    Cachex.Hook.broadcast(cache1, :broadcast, :result)

    # verify pre hooks aren't notified
    refute_receive(:broadcast)

    # broadcast using the cache name
    Cachex.Hook.broadcast(cache2, :broadcast, :result)

    # verify only one message is forwarded
    assert_receive(:broadcast)

    # ensure nil values come back when a bad cache name is used
    false = Cachex.Hook.broadcast(:missing_cache, :broadcast, :result)
  end

  # This test ensures that hooks can be correctly grouped into their execution
  # type, and that there is always an entry for both types (pre/post).
  test "grouping Hooks by type" do
    # create a pre and post hook
    hook1 = ForwardHook.create(%{ type:  :pre })
    hook2 = ForwardHook.create(%{ type: :post })

    # group various combinations
    result1 = Cachex.Hook.group_by_type(hook1)
    result2 = Cachex.Hook.group_by_type(hook2)
    result3 = Cachex.Hook.group_by_type([ hook1, hook2 ])

    # pull specific types
    result4 = Cachex.Hook.group_by_type(hook1, :post)
    result5 = Cachex.Hook.group_by_type(hook2, :pre)
    result6 = Cachex.Hook.group_by_type(hook1, :pre)
    result7 = Cachex.Hook.group_by_type(hook2, :post)

    # verify the first two groups use defaults
    assert(result1 == %{ pre: [ hook1 ], post: [ ] })
    assert(result2 == %{ pre: [ ], post: [ hook2 ] })

    # verify the third group contains both hooks
    assert(result3 == %{ pre: [ hook1 ], post: [ hook2 ] })

    # verify the fourth and fifth groups are empty lists
    assert(result4 == [ ])
    assert(result5 == [ ])

    # the sixth and seventh should be lists of each hook
    assert(result6 == [ hook1 ])
    assert(result7 == [ hook2 ])
  end

  # This test ensures that Hook notifications function correctly, trying various
  # Hook types and execution patterns. If the hook executes before the action,
  # we only ever receive the action as the message, as results will often not
  # exist. This is true if we use a post hook without the results flag set to true.
  # We also verify that non-async hooks block the chain of execution whilst they
  # wait for a response. This behaviour will be improved in future to clean up
  # after itself, but for now it's sufficient to validate a rough timeout - we
  # allow a delta of 10ms just because of Erlang's timers not being overly accurate.
  test "notifying a list of Hooks" do
    # create a pre Hook
    hook1 = ForwardHook.create(%{ type: :pre })

    # create a post Hook
    hook2 = ForwardHook.create(%{ type: :post })

    # create a pre hook with results
    hook3 = ForwardHook.create(%{ type: :pre, results: true })

    # create a post hook with results
    hook4 = ForwardHook.create(%{ type: :post, results: true })

    # create a synchronous hook
    hook5 = ExecuteHook.create(%{ async: false, max_timeout: 50 })

    # create a hook without initializing
    hook6 = ForwardHook.create(%{ })

    # initialize caches to initialize the hooks
    cache1 = Helper.create_cache([ hooks: hook1 ])
    cache2 = Helper.create_cache([ hooks: hook2 ])
    cache3 = Helper.create_cache([ hooks: hook3 ])
    cache4 = Helper.create_cache([ hooks: hook4 ])
    cache5 = Helper.create_cache([ hooks: hook5 ])

    # update our hooks from the caches
    [hook1] = Cachex.State.get(cache1).pre_hooks
    [hook2] = Cachex.State.get(cache2).post_hooks
    [hook3] = Cachex.State.get(cache3).pre_hooks
    [hook4] = Cachex.State.get(cache4).post_hooks
    [hook5] = Cachex.State.get(cache5).post_hooks

    # uninitialized hooks shouldn't emit
    Cachex.Hook.notify([ hook6 ], :hook6, :result)

    # ensure nothing is received
    refute_receive(:hook6)
    refute_receive({ :hook6, :result })

    # pre hooks only ever get the action
    Cachex.Hook.notify([ hook1, hook3 ], :pre_hooks, :result)

    # ensure only the action is received
    assert_receive(:pre_hooks)
    assert_receive(:pre_hooks)

    # post hooks can receive results if requested
    Cachex.Hook.notify([ hook2, hook4 ], :post_hooks, :result)

    # ensure the messages are received
    assert_receive(:post_hooks)
    assert_receive({ :post_hooks, :result })

    # synchronous hooks can block the notify call
    { time1, _value } = :timer.tc(fn ->
      Cachex.Hook.notify([ hook5 ], fn ->
        :timer.sleep(25)
        :sync_hook
      end)
    end)

    # ensure we received the message
    assert_receive(:sync_hook)

    # ensure it took roughly 25ms
    assert_in_delta(time1, 25000, 10000)

    # synchronous hooks can block the notify call up to a limit
    { time2, _value } = :timer.tc(fn ->
      Cachex.Hook.notify([ hook5 ], fn ->
        :timer.sleep(1000)
        :sync_hook
      end)
    end)

    # ensure it took roughly 50ms
    assert_in_delta(time2, 50000, 10000)
  end

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
