defmodule Cachex.WarmerTest do
  use CachexCase

  test "warmers which set basic values" do
    # create a test warmer to pass to the cache
    Helper.create_warmer(:basic_warmer, 50, fn _ ->
      {:ok, [{1, 1}]}
    end)

    # create a cache instance with a warmer
    cache = Helper.create_cache(warmers: [warmer(module: :basic_warmer)])

    # check that the key was warmed
    assert Cachex.get!(cache, 1) == 1
  end

  test "warmers which set values with options" do
    # create a test warmer to pass to the cache
    Helper.create_warmer(:options_warmer, 50, fn _ ->
      {:ok, [{1, 1}], [ttl: 60000]}
    end)

    # create a cache instance with a warmer
    cache = Helper.create_cache(warmers: [warmer(module: :options_warmer)])

    # check that the key was warmed
    assert Cachex.get!(cache, 1) == 1

    # check that there's a TTL
    assert Cachex.ttl!(cache, 1) != nil
  end

  test "warmers which don't set values" do
    # create a test warmer to pass to the cache
    Helper.create_warmer(:ignore_warmer, 50, fn _ ->
      :ignore
    end)

    # create a cache instance with a warmer
    cache = Helper.create_cache(warmers: [warmer(module: :ignore_warmer)])

    # check that the cache is empty
    assert Cachex.empty?(!cache)
  end

  test "warmers which aren't blocking" do
    # create a test warmer to pass to the cache
    Helper.create_warmer(:async_warmer, 50, fn _ ->
      :timer.sleep(3000)
      {:ok, [{1, 1}]}
    end)

    # create a cache instance with a warmer
    warmer = warmer(module: :async_warmer, async: true)
    cache = Helper.create_cache(warmers: [warmer])

    # check that the key was not warmed
    assert Cachex.get!(cache, 1) == nil
  end

  test "providing warmers with states" do
    # create a test warmer to pass to the cache
    Helper.create_warmer(:state_warmer, 50, fn state ->
      {:ok, [{"state", state}]}
    end)

    # current timestamp to use as state
    state = :os.timestamp()

    # create a cache instance with a warmer
    cache =
      Helper.create_cache(
        warmers: [warmer(module: :state_warmer, state: state)]
      )

    # check that the key was warmed with state
    assert Cachex.get!(cache, "state") == state
  end

  test "warmer triggers hook for sync and async warmers" do
    expected_values = [{1, 1}]
    expected_opts = [ttl: 1_000]

    warmer_state = %{
      expected_values: expected_values,
      expected_opts: expected_opts
    }

    hook = ForwardHook.create()

    # create a test warmer to pass to the cache
    Helper.create_warmer(:test_warmer, 500, fn state ->
      {:ok, state.expected_values, state.expected_opts}
    end)

    for async <- [true, false] do
      # create a cache instance with a warmer and hook
      Helper.create_cache(
        warmers: [
          warmer(module: :test_warmer, state: warmer_state, async: async)
        ],
        hooks: [hook]
      )

      assert_receive {{:put_many, [^expected_values, ^expected_opts]},
                      {:ok, true}}
    end
  end
end
