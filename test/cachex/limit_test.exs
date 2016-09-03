defmodule Cachex.LimitTest do
  use PowerAssert, async: false

  test "parsing a limit using an existing limit" do
    limit = %Cachex.Limit{
      limit: 500,
      policy: Cachex.Policy.LRW,
      reclaim: 0.3
    }

    assert(Cachex.Limit.parse(limit) == limit)
  end

  test "parsing a limit using an entry count" do
    assert(Cachex.Limit.parse(500) == %Cachex.Limit{
      limit: 500,
      policy: Cachex.Policy.LRW,
      reclaim: 0.1
    })
  end

  test "parsing a limit using an invalid value" do
    assert(Cachex.Limit.parse(:missing) == %Cachex.Limit{
      limit: nil,
      policy: Cachex.Policy.LRW,
      reclaim: 0.1
    })
  end

  test "parsing a limit using an invalid policy" do
    limit = %Cachex.Limit{
      limit: 500,
      policy: Cachex.Policy.Missing,
      reclaim: 0.3
    }

    assert(Cachex.Limit.parse(limit) == %Cachex.Limit{
      limit: 500,
      policy: Cachex.Policy.LRW,
      reclaim: 0.3
    })
  end

  test "parsing a limit using an invalid upper reclaim bound" do
    limit = %Cachex.Limit{
      limit: 500,
      policy: Cachex.Policy.Missing,
      reclaim: 15
    }

    assert(Cachex.Limit.parse(limit) == %Cachex.Limit{
      limit: 500,
      policy: Cachex.Policy.LRW,
      reclaim: 0.1
    })
  end

  test "parsing a limit using an invalid lower reclaim bound" do
    limit = %Cachex.Limit{
      limit: 500,
      policy: Cachex.Policy.Missing,
      reclaim: -1
    }

    assert(Cachex.Limit.parse(limit) == %Cachex.Limit{
      limit: 500,
      policy: Cachex.Policy.LRW,
      reclaim: 0.1
    })
  end

  test "converting a Limit to a Hook returns a list of hooks" do
    limit = %Cachex.Limit{
      limit: 500,
      policy: Cachex.Policy.LRW,
      reclaim: 0.3
    }

    assert(Cachex.Limit.to_hooks(limit) == [ %Cachex.Hook{
      args: { 500, 0.3 },
      async: true,
      max_timeout: nil,
      module: Cachex.Policy.LRW,
      provide: [:worker],
      ref: nil,
      results: true,
      server_args: [],
      type: :post
    } ])
  end

  test "converting a nil Limit to a Hook returns an empty list" do
    assert(Cachex.Limit.to_hooks(%Cachex.Limit{ }) == [ ])
  end

end
