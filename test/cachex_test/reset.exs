defmodule CachexTest.Reset do
  use PowerAssert

  alias Cachex.Hook

  setup do
    { :ok, cache: TestHelper.create_cache() }
  end

  test "resetting empties a cache and resets the state of hooks" do
    hook = %Hook{
      args: [:base],
      module: __MODULE__.LastActionHook,
      type: :pre
    }

    cache = TestHelper.create_cache([ hooks: hook ])

    set_result = Cachex.set(cache, "key", "value")
    assert(set_result == { :ok, true })

    size_result = Cachex.size(cache)
    assert(size_result == { :ok, 1 })

    hook =
      cache
      |> Cachex.inspect!(:worker)
      |> Map.get(:options)
      |> Map.get(:pre_hooks)
      |> Hook.hook_by_module(__MODULE__.LastActionHook)

    hook_state = Hook.call(hook, :state)
    assert(hook_state == { :size, [] })

    reset_result = Cachex.reset(cache)
    assert(reset_result == { :ok, true })

    hook_state = Hook.call(hook, :state)
    assert(hook_state == :base)

    size_result = Cachex.size(cache)
    assert(size_result == { :ok, 0 })

    hook_state = Hook.call(hook, :state)
    assert(hook_state == { :size, [] })
  end

  test "resetting only a cache and no hooks" do
    hook = %Hook{
      args: [:base],
      module: __MODULE__.LastActionHook,
      type: :pre
    }

    cache = TestHelper.create_cache([ hooks: hook ])

    set_result = Cachex.set(cache, "key", "value")
    assert(set_result == { :ok, true })

    size_result = Cachex.size(cache)
    assert(size_result == { :ok, 1 })

    hook =
      cache
      |> Cachex.inspect!(:worker)
      |> Map.get(:options)
      |> Map.get(:pre_hooks)
      |> Hook.hook_by_module(__MODULE__.LastActionHook)

    hook_state = Hook.call(hook, :state)
    assert(hook_state == { :size, [] })

    reset_result = Cachex.reset(cache, only: :cache)
    assert(reset_result == { :ok, true })

    hook_state = Hook.call(hook, :state)
    assert(hook_state == { :size, [] })

    size_result = Cachex.size(cache)
    assert(size_result == { :ok, 0 })
  end

  test "resetting only hooks and no cache" do
    hook = %Hook{
      args: [:base],
      module: __MODULE__.LastActionHook,
      type: :pre
    }

    cache = TestHelper.create_cache([ hooks: hook ])

    set_result = Cachex.set(cache, "key", "value")
    assert(set_result == { :ok, true })

    size_result = Cachex.size(cache)
    assert(size_result == { :ok, 1 })

    hook =
      cache
      |> Cachex.inspect!(:worker)
      |> Map.get(:options)
      |> Map.get(:pre_hooks)
      |> Hook.hook_by_module(__MODULE__.LastActionHook)

    hook_state = Hook.call(hook, :state)
    assert(hook_state == { :size, [] })

    reset_result = Cachex.reset(cache, only: :hooks)
    assert(reset_result == { :ok, true })

    hook_state = Hook.call(hook, :state)
    assert(hook_state == :base)

    size_result = Cachex.size(cache)
    assert(size_result == { :ok, 1 })
  end

  test "resetting only a whitelist of hooks" do
    hooks = [
      %Hook{
        args: [:base],
        module: __MODULE__.LastActionHook,
        type: :pre
      },
      %Hook{
        args: [:base],
        module: __MODULE__.LastFunctionHook,
        type: :pre
      }
    ]

    cache = TestHelper.create_cache([ hooks: hooks ])

    size_result = Cachex.size(cache)
    assert(size_result == { :ok, 0 })

    pre_hooks =
      cache
      |> Cachex.inspect!(:worker)
      |> Map.get(:options)
      |> Map.get(:pre_hooks)

    actions_hook  = Hook.hook_by_module(pre_hooks, __MODULE__.LastActionHook)
    function_hook = Hook.hook_by_module(pre_hooks, __MODULE__.LastFunctionHook)

    action_hook_state = Hook.call(actions_hook, :state)
    assert(action_hook_state == { :size, [] })

    function_hook_state = Hook.call(function_hook, :state)
    assert(function_hook_state == :size)

    reset_result = Cachex.reset(cache, hooks: [ __MODULE__.LastActionHook ])
    assert(reset_result == { :ok, true })

    action_hook_state = Hook.call(actions_hook, :state)
    assert(action_hook_state == :base)

    function_hook_state = Hook.call(function_hook, :state)
    assert(function_hook_state == :size)
  end

  test "resetting with a worker instance", state do
    state_result = Cachex.inspect!(state.cache, :worker)
    assert(Cachex.reset(state_result) == { :ok, true })
  end

end

defmodule CachexTest.Reset.LastActionHook do
  use Cachex.Hook

  def init(base) do
    { :ok, base }
  end

  def handle_notify(action, _state) do
    { :ok, action }
  end

  def handle_call(:state, state) do
    { :ok, state, state }
  end
end

defmodule CachexTest.Reset.LastFunctionHook do
  use Cachex.Hook

  def init(base) do
    { :ok, base }
  end

  def handle_notify(action, _state) do
    { :ok, elem(action, 0) }
  end

  def handle_call(:state, state) do
    { :ok, state, state }
  end
end
