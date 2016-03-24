defmodule CachexTest.Options do
  use PowerAssert

  alias Cachex.Options

  setup do
    { :ok, name: TestHelper.gen_random_string_of_length(16) |> String.to_atom }
  end

  test "options parsing requires a valid atom as a cache name", state do
    assert_raise ArgumentError, "Cache name must be a valid atom", &(Options.parse/0)
    assert_raise ArgumentError, "Cache name must be a valid atom", fn ->
      Options.parse(nil)
    end
    assert_raise ArgumentError, "Cache name must be a valid atom", fn ->
      Options.parse([name: "test"])
    end

    Options.parse([name: state.name])
  end

  test "options can generate default ETS options for Mnesia", state do
    parsed_opts = Options.parse(name: state.name)

    assert(parsed_opts.ets_opts == [
      { :read_concurrency, true },
      { :write_concurrency, true }
    ])
  end

  test "options can accept customized ETS options for Mnesia", state do
    custom_opts = [
      { :read_concurrency, false },
      { :write_concurrency, false }
    ]

    parsed_opts = Options.parse(name: state.name, ets_opts: custom_opts)

    assert(parsed_opts.ets_opts == custom_opts)
  end

  test "options allows a default ttl value", state do
    parsed_opts = Options.parse(name: state.name, default_ttl: :timer.seconds(5))

    assert(parsed_opts.default_ttl == :timer.seconds(5))
    assert(parsed_opts.ttl_interval == :timer.seconds(1))
  end

  test "options does not allow negative default ttls", state do
    parsed_opts = Options.parse(name: state.name, default_ttl: :timer.seconds(-5))

    assert(parsed_opts.default_ttl == nil)
    assert(parsed_opts.ttl_interval == nil)
  end

  test "options allows custom ttl intervals", state do
    parsed_opts = Options.parse(name: state.name, ttl_interval: :timer.seconds(2))

    assert(parsed_opts.ttl_interval == :timer.seconds(2))
  end

  test "options does not allow negative ttl intervals", state do
    parsed_opts = Options.parse(name: state.name, ttl_interval: :timer.seconds(-2))

    assert(parsed_opts.ttl_interval == nil)
  end

  test "options accepts a list of remote nodes", state do
    nodes = [node(),:"anode@ahost"]

    parsed_opts = Options.parse(name: state.name, nodes: nodes)

    assert(parsed_opts.nodes == nodes)
    assert(parsed_opts.remote == true)
  end

  test "options does not set remote to true if only this node is added", state do
    parsed_opts = Options.parse(name: state.name, nodes: [node()])

    assert(parsed_opts.nodes == [node()])
    assert(parsed_opts.remote == false)
  end

  test "options sets remote to true if overridden", state do
    parsed_opts = Options.parse(name: state.name, remote: true)

    assert(parsed_opts.remote == true)
  end

  test "options sets transactional to true if provided", state do
    parsed_opts = Options.parse(name: state.name, transactional: true)

    assert(parsed_opts.transactional == true)
  end

  test "options accepts a default fallback function", state do
    default_function = &(&1)

    parsed_opts = Options.parse(name: state.name, default_fallback: default_function)

    assert(parsed_opts.default_fallback == default_function)
    assert(parsed_opts.fallback_args == [])
  end

  test "options accepts a list of fallback arguments", state do
    args = [1,2,3]

    parsed_opts = Options.parse(name: state.name, fallback_args: args)

    assert(parsed_opts.fallback_args == args)
  end

  test "options accepts and starts a list of pre hooks", state do
    hook = %Cachex.Hook{
      module: Cachex.Stats,
      type: :pre,
      results: true,
      server_args: [
        name: Cachex.Util.stats_for_cache(state.name)
      ]
    }

    parsed_opts = Options.parse(name: state.name, hooks: hook)

    pre_hooks =
      parsed_opts.pre_hooks
      |> Enum.map(&(%Cachex.Hook{ &1 | ref: nil }))

    assert(pre_hooks == [hook])
  end

  test "options accepts and starts a list of post hooks", state do
    hook = %Cachex.Hook{
      module: Cachex.Stats,
      type: :post,
      results: true,
      server_args: [
        name: Cachex.Util.stats_for_cache(state.name)
      ]
    }

    parsed_opts = Options.parse(name: state.name, hooks: hook)

    post_hooks =
      parsed_opts.post_hooks
      |> Enum.map(&(%Cachex.Hook{ &1 | ref: nil }))

    assert(post_hooks == [hook])
  end

  test "options adds a stats hook if record_stats is true", state do
    hook = %Cachex.Hook{
      module: Cachex.Stats,
      type: :post,
      results: true,
      server_args: [
        name: Cachex.Util.stats_for_cache(state.name)
      ]
    }

    parsed_opts = Options.parse(name: state.name, record_stats: true)

    post_hooks =
      parsed_opts.post_hooks
      |> Enum.map(&(%Cachex.Hook{ &1 | ref: nil }))

    assert(post_hooks == [hook])
  end

end
