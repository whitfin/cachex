defmodule Cachex.LimitTest do
  use CachexCase

  # This test just adds a check to make sure that we're aware of the default values
  # inside a Limit struct. This doesn't serve much as a test, more a warning that
  # the defaults may have changed unexpectedly.
  test "default values inside a Limit" do
    # create a base limit
    limit1 = %Cachex.Limit{ }

    # create a comparison
    limit2 = %Cachex.Limit{
      limit: nil,
      policy: Cachex.Policy.LRW,
      reclaim: 0.1,
      options: []
    }

    # they should be the same
    assert(limit1 == limit2)
  end

  # This test verifies the parsing ability of the Limit module which should be
  # able to parse a value into a Limit struct. The parse function accepts either
  # an existing Limit, or a maximum size so we have to validate both. We also
  # run each value through type checking in order to make sure the values are
  # of the correct type and format in order to void errors later in execution.
  test "parsing values into a Limit" do
    # create a base limit
    base = %Cachex.Limit{ }

    # create a valid limit using all fields
    limit1 = %Cachex.Limit{ base | limit: 500, reclaim: 0.3, options: [ test: true ] }
    limit2 = %Cachex.Limit{ base | limit: 1 }
    limit3 = %Cachex.Limit{ base | policy: Cachex.Policy.LRW }
    limit4 = %Cachex.Limit{ base | reclaim: 0.5 }
    limit5 = %Cachex.Limit{ base | options: [ test: true ] }

    # create invalid limits to test failure
    limit6  = %Cachex.Limit{ base | limit: -1 }
    limit7  = %Cachex.Limit{ base | policy: Cachex.Policy.Nah }
    limit8  = %Cachex.Limit{ base | reclaim: 0.0 }
    limit9  = %Cachex.Limit{ base | reclaim: 1.1 }
    limit10 = %Cachex.Limit{ base | options: true }

    # parse out our valid limits
    { :ok, result1 } = Cachex.Limit.parse(limit1)
    { :ok, result2 } = Cachex.Limit.parse(limit2)
    { :ok, result3 } = Cachex.Limit.parse(limit3)
    { :ok, result4 } = Cachex.Limit.parse(limit4)
    { :ok, result5 } = Cachex.Limit.parse(limit5)

    # parse invalid limits for testing
    result6  = Cachex.Limit.parse(limit6)
    result7  = Cachex.Limit.parse(limit7)
    result8  = Cachex.Limit.parse(limit8)
    result9  = Cachex.Limit.parse(limit9)
    result10 = Cachex.Limit.parse(limit10)

    # parse out using a numeric literal
    { :ok, result11 } = Cachex.Limit.parse(500000)

    # verify all the valid limits
    assert(result1 == limit1)
    assert(result2 == limit2)
    assert(result3 == limit3)
    assert(result4 == limit4)
    assert(result5 == limit5)

    # verify the number literal is used as a limit field
    assert(result11 == %Cachex.Limit{ base | limit: 500000 })

    # verify the invalid limits fail the parse
    assert(result6  == { :error, :invalid_limit })
    assert(result7  == { :error, :invalid_limit })
    assert(result8  == { :error, :invalid_limit })
    assert(result9  == { :error, :invalid_limit })
    assert(result10 == { :error, :invalid_limit })
  end

  # This test checks the conversion of Limits into Hooks, simply by passing some
  # different Limit structs into the to_hooks function in order to validate that
  # they're converted to the correct list of hooks (or no hooks, if applicable).
  # Hooks are determined based on the Policy backing the Limit, so we need to
  # test conversion with each Policy type currently accepted.
  test "converting a Limit into Hooks" do
    # create a limit with no size
    limit1 = %Cachex.Limit{ }

    # create limits for each policy
    limit2 = %Cachex.Limit{ limit: 500, policy: Cachex.Policy.LRW, reclaim: 0.1 }

    # convert all limits to hooks
    hooks1 = Cachex.Limit.to_hooks(limit1)
    hooks2 = Cachex.Limit.to_hooks(limit2)

    # check the first limit makes no hooks
    assert(hooks1 == [ ])

    # check the second limit creates a hook
    assert(hooks2 == [
      %Cachex.Hook{
        args: limit2,
        module: Cachex.Policy.LRW,
        provide: [ :cache ]
      }
    ])
  end
end
