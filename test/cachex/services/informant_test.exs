defmodule Cachex.Services.InformantTest do
  use Cachex.Test.Case

  # Bind any required hooks for test execution
  setup_all do
    # bind the required forward hooks for testing
    ForwardHook.bind(
      informant_forward_hook_pre: [type: :pre],
      informant_forward_hook_post: [type: :post],
      informant_forward_hook_actions_get: [actions: [:get]]
    )

    # bind the required execute hooks for testing
    ExecuteHook.bind(
      informant_execute_hook_sync: [async: false],
      informant_execute_hook_sync_timeout: [async: false, timeout: 50]
    )

    # done
    :ok
  end

  # This test ensures that we are able to broadcast a set of results from an out
  # of bound process to all post_hooks (and only post_hooks).
  test "broadcasting results to a list of hooks" do
    # create a pre and post hook
    hook1 = ForwardHook.create(:informant_forward_hook_pre)
    hook2 = ForwardHook.create(:informant_forward_hook_post)
    hook3 = ForwardHook.create(:informant_forward_hook_actions_get)

    # start a cache with the hooks
    cache1 = TestUtils.create_cache(hooks: [hook1])
    cache2 = TestUtils.create_cache(hooks: [hook2])
    cache3 = TestUtils.create_cache(hooks: [hook3])

    # grab a state instance for the broadcast
    state1 = Services.Overseer.lookup(cache1)
    state2 = Services.Overseer.lookup(cache2)
    state3 = Services.Overseer.lookup(cache3)

    # broadcast using the cache name
    Services.Informant.broadcast(state1, {:action, []}, :result)

    # verify pre hooks aren't notified
    refute_receive({{:action, []}, nil})

    # broadcast using the cache name
    Services.Informant.broadcast(state2, {:action, []}, :result)

    # verify only one message is forwarded
    assert_receive({{:action, []}, :result})

    # send an unwhitelisted message
    Services.Informant.broadcast(state3, {:action, []}, :result)

    # verify hooks aren't notified
    refute_receive({{:action, []}, nil})
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
    hook1 = ForwardHook.create(:informant_forward_hook_pre)

    # create a post Hook
    hook2 = ForwardHook.create(:informant_forward_hook_post)

    # create a synchronous hook
    hook3 = ExecuteHook.create(:informant_execute_hook_sync)

    # create a synchronous hook
    hook4 = ExecuteHook.create(:informant_execute_hook_sync_timeout)

    # create a named hook
    hook5 =
      ForwardHook.create(
        :informant_forward_hook_pre,
        :informant_forward_hook_pre_named
      )

    # create a hook without initializing
    hook6 = ForwardHook.create()

    # initialize caches to initialize the hooks
    cache1 = TestUtils.create_cache(hooks: hook1)
    cache2 = TestUtils.create_cache(hooks: hook2)
    cache3 = TestUtils.create_cache(hooks: hook3)
    cache4 = TestUtils.create_cache(hooks: hook4)
    cache5 = TestUtils.create_cache(hooks: hook5)

    # update our hooks from the caches
    cache(hooks: hooks(pre: [hook1])) = Services.Overseer.lookup(cache1)
    cache(hooks: hooks(post: [hook2])) = Services.Overseer.lookup(cache2)
    cache(hooks: hooks(post: [hook3])) = Services.Overseer.lookup(cache3)
    cache(hooks: hooks(post: [hook4])) = Services.Overseer.lookup(cache4)
    cache(hooks: hooks(pre: [hook5])) = Services.Overseer.lookup(cache5)

    # uninitialized hooks shouldn't emit
    Services.Informant.notify([hook6], {:action, []}, :result)

    # ensure nothing is received
    refute_receive({{:action, []}, :result})

    # pre hooks only ever get the action
    Services.Informant.notify([hook1], {:pre_hooks, []}, :result)
    Services.Informant.notify([hook5], {:pre_hooks, []}, :result)

    # ensure only the action is received
    assert_receive({{:pre_hooks, []}, :result})
    assert_receive({{:pre_hooks, []}, :result})

    # post hooks can receive results if requested
    Services.Informant.notify([hook2], {:post_hooks, []}, :result)

    # ensure the messages are received
    assert_receive({{:post_hooks, []}, :result})

    # synchronous hooks can block the notify call
    {time1, _value} =
      :timer.tc(fn ->
        Services.Informant.notify(
          [hook3],
          {:exec,
           fn ->
             :timer.sleep(25)
             :sync_hook
           end},
          nil
        )
      end)

    # ensure we received the message
    assert_receive(:sync_hook)

    # ensure it took roughly 25ms
    assert_in_delta(time1, 25000, 10000)

    # synchronous hooks can block the notify call up to a limit
    {time2, _value} =
      :timer.tc(fn ->
        Services.Informant.notify(
          [hook4],
          {:exec,
           fn ->
             :timer.sleep(1000)
             :sync_hook
           end},
          nil
        )
      end)

    # ensure it took roughly 50ms
    assert_in_delta(time2, 57500, 7500)
  end
end
