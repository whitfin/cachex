defmodule Cachex.WarmerTest do
  use Cachex.Test.Case

  test "warmers which set basic values" do
    # create a test warmer to pass to the cache
    TestUtils.create_warmer(:basic_warmer, fn _ ->
      {:ok, [{1, 1}]}
    end)

    # create a cache instance with a warmer
    cache = TestUtils.create_cache(warmers: [warmer(module: :basic_warmer)])

    # check that the key was warmed
    assert Cachex.get!(cache, 1) == 1
  end

  test "warmers which set values with options" do
    # create a test warmer to pass to the cache
    TestUtils.create_warmer(:options_warmer, fn _ ->
      {:ok, [{1, 1}], [expire: 60000]}
    end)

    # create a cache instance with a warmer
    cache = TestUtils.create_cache(warmers: [warmer(module: :options_warmer)])

    # check that the key was warmed
    assert Cachex.get!(cache, 1) == 1

    # check that there's a TTL
    assert Cachex.ttl!(cache, 1) != nil
  end

  test "warmers which don't set values" do
    # create a test warmer to pass to the cache
    TestUtils.create_warmer(:ignore_warmer, fn _ ->
      :ignore
    end)

    # create a cache instance with a warmer
    cache = TestUtils.create_cache(warmers: [warmer(module: :ignore_warmer)])

    # check that the cache is empty
    assert Cachex.empty?(!cache)
  end

  test "warmers which aren't blocking" do
    # create a test warmer to pass to the cache
    TestUtils.create_warmer(:optional_warmer, fn _ ->
      :timer.sleep(3000)
      {:ok, [{1, 1}]}
    end)

    # create a cache instance with a warmer
    warmer = warmer(module: :optional_warmer, required: false)
    cache = TestUtils.create_cache(warmers: [warmer])

    # check that the key was not warmed
    assert Cachex.get!(cache, 1) == nil
  end

  test "providing warmers with states" do
    # create a test warmer to pass to the cache
    TestUtils.create_warmer(:state_warmer, fn state ->
      {:ok, [{"state", state}]}
    end)

    # current timestamp to use as state
    state = :os.timestamp()

    # create a cache instance with a warmer
    cache =
      TestUtils.create_cache(
        warmers: [warmer(module: :state_warmer, state: state)]
      )

    # check that the key was warmed with state
    assert Cachex.get!(cache, "state") == state
  end

  test "triggering cache hooks from within warmers" do
    # create a test warmer to pass to the cache
    TestUtils.create_warmer(:hook_warmer_optional, fn _ ->
      {:ok, [{1, 1}]}
    end)

    # create a test warmer to pass to the cache
    TestUtils.create_warmer(:hook_warmer_required, fn _ ->
      {:ok, [{2, 2}]}
    end)

    # create a hook to forward messages
    hook = ForwardHook.create()

    # create a cache instance with a warmer and hook
    TestUtils.create_cache(
      hooks: [hook],
      warmers: [
        warmer(module: :hook_warmer_optional, interval: 15000, required: false),
        warmer(module: :hook_warmer_required, interval: 15000, required: true)
      ]
    )

    # ensure that we receive the creation of both warmers
    assert_receive({{:put_many, [[{1, 1}], []]}, {:ok, true}})
    assert_receive({{:put_many, [[{2, 2}], []]}, {:ok, true}})
  end
end
