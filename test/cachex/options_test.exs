defmodule Cachex.OptionsTest do
  use Cachex.Test.Case

  # Bind any required hooks for test execution
  setup_all do
    ForwardHook.bind(
      options_pre_forward_hook: [type: :pre],
      options_post_forward_hook: [type: :post]
    )

    :ok
  end

  # Options parsing should add the cache name to the returned state, so this test
  # will just ensure that this is done correctly.
  test "adding a cache name to the state" do
    # grab a cache name
    name = Helper.create_name()

    # parse the options into a validated cache state
    assert match?({:ok, cache(name: ^name)}, Cachex.Options.parse(name, []))
  end

  # This test ensures the integrity of the basic option parser provided for use
  # when parsing cache options. We need to test the ability to retrieve a value
  # based on a condition, but also returning default values in case of condition
  # failure or error.
  test "getting options from a Keyword List" do
    # our base option set
    options = [positive: 10, negative: -10]

    # our base condition
    condition = &(is_number(&1) and &1 > 0)

    # parse out using a true condition
    result1 = Cachex.Options.get(options, :positive, condition)

    # parse out using a false condition (should return a default)
    result2 = Cachex.Options.get(options, :negative, condition)

    # parse out using an error condition (should return a custom default)
    result3 =
      Cachex.Options.get(
        options,
        :negative,
        fn _ ->
          raise ArgumentError
        end,
        0
      )

    # condition true means we return the value
    assert(result1 == 10)

    # condition false and no default means we return nil
    assert(result2 == nil)

    # condition false with a default returns the default
    assert(result3 == 0)
  end

  # This test makes sure that we can correctly parse out commands which are to
  # be attached to the cache. We make sure to try with commands which are both
  # valid and invalid, as well as badly formed command options. We also make
  # sure (via `v_cmds3`) that we only keep the first definition of a command.
  # This is because commands are provided as a Keyword List, but internally stored
  # as a Map - so we need to make sure the kept command is intuitive for the user.
  test "parsing :commands flags" do
    # grab a cache name
    name = Helper.create_name()

    # define some functions
    fun1 = fn _ -> [1, 2, 3] end
    fun2 = fn _ -> [3, 2, 1] end

    # define valid command lists
    v_cmds1 = [commands: []]
    v_cmds2 = [commands: [lpop: command(type: :read, execute: fun1)]]
    v_cmds3 = [commands: %{lpop: command(type: :read, execute: fun1)}]

    v_cmds4 = [
      commands: [
        lpop: command(type: :read, execute: fun1),
        lpop: command(type: :write, execute: fun2)
      ]
    ]

    # define invalid command lists
    i_cmds1 = [commands: [1]]
    i_cmds2 = [commands: {1}]
    i_cmds3 = [commands: [lpop: 1]]

    # attempt to validate
    {:ok, cache(commands: commands1)} = Cachex.Options.parse(name, v_cmds1)
    {:ok, cache(commands: commands2)} = Cachex.Options.parse(name, v_cmds2)
    {:ok, cache(commands: commands3)} = Cachex.Options.parse(name, v_cmds3)
    {:ok, cache(commands: commands4)} = Cachex.Options.parse(name, v_cmds4)

    # the first two should be parsed into maps
    assert(commands1 == %{})
    assert(commands2 == %{lpop: command(type: :read, execute: fun1)})
    assert(commands3 == %{lpop: command(type: :read, execute: fun1)})

    # the fourth should keep only the first implementation
    assert(commands4 == %{lpop: command(type: :read, execute: fun1)})

    # parse the invalid lists
    {:error, msg} = Cachex.Options.parse(name, i_cmds1)
    {:error, ^msg} = Cachex.Options.parse(name, i_cmds2)
    {:error, ^msg} = Cachex.Options.parse(name, i_cmds3)

    # should return an error
    assert(msg == :invalid_command)
  end

  # This test will verify the parsing of compression flags to determine whether
  # a cache has them enabled or disabled. This is simply checking whether the flag
  # is set to true or false, and the default.
  test "parsing :compressed flags" do
    # grab a cache name
    name = Helper.create_name()

    # parse our values as options
    {:ok, cache(compressed: comp1)} =
      Cachex.Options.parse(name, compressed: true)

    {:ok, cache(compressed: comp2)} =
      Cachex.Options.parse(name, compressed: false)

    {:ok, cache(compressed: comp3)} = Cachex.Options.parse(name, [])

    # the first one should be truthy, and the latter two falsey
    assert comp1
    refute comp2
    refute comp3
  end

  # This test verifies the parsing of TTL related flags. We have to test various
  # combinations of :ttl_interval and :default_ttl to verify each state correctly.
  test "parsing :expiration flags" do
    # grab a cache name
    name = Helper.create_name()

    # parse out valid combinations
    {:ok, cache(expiration: exp1)} =
      Cachex.Options.parse(name, expiration: expiration(default: 1))

    {:ok, cache(expiration: exp2)} =
      Cachex.Options.parse(name, expiration: expiration(default: nil))

    {:ok, cache(expiration: exp3)} =
      Cachex.Options.parse(name, expiration: expiration(interval: 1))

    {:ok, cache(expiration: exp4)} =
      Cachex.Options.parse(name, expiration: expiration(interval: nil))

    {:ok, cache(expiration: exp5)} =
      Cachex.Options.parse(name, expiration: expiration(lazy: true))

    {:ok, cache(expiration: exp6)} =
      Cachex.Options.parse(name, expiration: expiration(lazy: false))

    {:ok, cache(expiration: exp7)} = Cachex.Options.parse(name, [])

    # verify all valid states parse correctly
    assert exp1 == expiration(default: 1, interval: 3000, lazy: true)
    assert exp2 == expiration(default: nil, interval: 3000, lazy: true)
    assert exp3 == expiration(default: nil, interval: 1, lazy: true)
    assert exp4 == expiration(default: nil, interval: nil, lazy: true)
    assert exp5 == expiration(default: nil, interval: 3000, lazy: true)
    assert exp6 == expiration(default: nil, interval: 3000, lazy: false)
    assert exp7 == expiration(default: nil, interval: 3000, lazy: true)

    # parse out invalid combinations
    {:error, msg} =
      Cachex.Options.parse(name, expiration: expiration(default: -1))

    {:error, ^msg} =
      Cachex.Options.parse(name, expiration: expiration(default: "1"))

    {:error, ^msg} =
      Cachex.Options.parse(name, expiration: expiration(interval: -1))

    {:error, ^msg} =
      Cachex.Options.parse(name, expiration: expiration(interval: "1"))

    {:error, ^msg} =
      Cachex.Options.parse(name, expiration: expiration(lazy: nil))

    {:error, ^msg} =
      Cachex.Options.parse(name, expiration: expiration(lazy: "1"))

    {:error, ^msg} = Cachex.Options.parse(name, expiration: "expiration")

    # check the error message on the failed states
    assert msg == :invalid_expiration
  end

  # Every cache can have a default fallback implementation which is used in case
  # of no fallback provided against cache reads. The only constraint here is that
  # the provided value is a valid function (of any arity).
  test "parsing :fallback flags" do
    # grab a cache name
    name = Helper.create_name()

    # define our falbacks
    fallback1 = fallback()
    fallback2 = fallback(default: &String.reverse/1)
    fallback3 = fallback(default: &String.reverse/1, state: {})
    fallback4 = fallback(state: {})
    fallback5 = &String.reverse/1
    fallback6 = {}

    # parse all the valid fallbacks into caches
    {:ok, cache(fallback: fallback1)} =
      Cachex.Options.parse(name, fallback: fallback1)

    {:ok, cache(fallback: fallback2)} =
      Cachex.Options.parse(name, fallback: fallback2)

    {:ok, cache(fallback: fallback3)} =
      Cachex.Options.parse(name, fallback: fallback3)

    {:ok, cache(fallback: fallback4)} =
      Cachex.Options.parse(name, fallback: fallback4)

    {:ok, cache(fallback: fallback5)} =
      Cachex.Options.parse(name, fallback: fallback5)

    {:error, msg} = Cachex.Options.parse(name, fallback: fallback6)

    # the first should use defaults
    assert(fallback1 == fallback())

    # the second and fifth should have an action but no state
    assert(fallback2 == fallback(default: &String.reverse/1))
    assert(fallback5 == fallback(default: &String.reverse/1))

    # the third should have both an action and state
    assert(fallback3 == fallback(default: &String.reverse/1, state: {}))

    # the fourth should have a state but no action
    assert(fallback4 == fallback(state: {}))

    # an invalid fallback should actually fail
    assert(msg == :invalid_fallback)
  end

  # This test will ensure that we can parse Hook values successfully. Hooks can
  # be provided as either a List or a single Hook. We also need to check that
  # Hooks are grouped into the correct pre/post groups inside the state.
  test "parsing :hooks flags" do
    # grab a cache name
    name = Helper.create_name()

    # create our pre hook
    pre_hook = ForwardHook.create(:options_pre_forward_hook)

    # create our post hook
    post_hook = ForwardHook.create(:options_post_forward_hook)

    # parse out valid hook combinations
    {:ok, cache(hooks: hooks1)} =
      Cachex.Options.parse(name, hooks: [pre_hook, post_hook])

    {:ok, cache(hooks: hooks2)} = Cachex.Options.parse(name, hooks: pre_hook)
    {:ok, cache(hooks: hooks3)} = Cachex.Options.parse(name, [])

    # parse out invalid hook combinations
    {:error, msg} = Cachex.Options.parse(name, hooks: "[hooks]")
    {:error, ^msg} = Cachex.Options.parse(name, hooks: hook(module: Missing))

    # check the hook groupings for the first state
    assert(hooks1 == hooks(pre: [pre_hook], post: [post_hook]))

    # check the hook groupings in the second state
    assert(hooks2 == hooks(pre: [pre_hook], post: []))

    # check the third state uses hook defaults
    assert(hooks3 == hooks())

    # check the invalid hook message
    assert(msg == :invalid_hook)
  end

  # This test ensures that the max size options can be correctly parsed. Parsing
  # this flag will set the Limit field inside the returned state, so it needs to
  # be checked. It will also add any Limit hooks to the hooks list, so this needs
  # to also be verified within this test.
  test "parsing :limit flags" do
    # grab a cache name
    name = Helper.create_name()

    # create a default limit
    default = limit()

    # our cache limit
    max_size = 500
    c_limits = limit(size: max_size)

    # parse options with a valid max_size
    {:ok, cache(hooks: hooks1, limit: limit1)} =
      Cachex.Options.parse(name, limit: max_size)

    {:ok, cache(hooks: hooks2, limit: limit2)} =
      Cachex.Options.parse(name, limit: c_limits)

    {:ok, cache(hooks: hooks3, limit: limit3)} = Cachex.Options.parse(name, [])

    # parse options with invalid max_size
    {:error, msg} = Cachex.Options.parse(name, limit: "max_size")

    # check the first and second states have limits
    assert(limit1 == c_limits)
    assert(limit2 == c_limits)
    assert(hooks1 == hooks(pre: [], post: Cachex.Policy.LRW.hooks(c_limits)))
    assert(hooks2 == hooks(pre: [], post: Cachex.Policy.LRW.hooks(c_limits)))

    # check the third has no limits attached
    assert(limit3 == default)
    assert(hooks3 == hooks(pre: [], post: []))

    # check the fourth causes an error
    assert(msg == :invalid_limit)
  end

  # This test will verify the parsing of compression flags to determine whether
  # a cache has them enabled or disabled. This is simply checking whether the flag
  # is set to true or false, and the default.
  test "parsing :ordered flags" do
    # grab a cache name
    name = Helper.create_name()

    # parse our values as options
    {:ok, cache(ordered: ordered1)} =
      Cachex.Options.parse(name, ordered: true)

    {:ok, cache(ordered: ordered2)} =
      Cachex.Options.parse(name, ordered: false)

    {:ok, cache(ordered: ordered3)} = Cachex.Options.parse(name, [])

    assert ordered1
    refute ordered2
    refute ordered3
  end

  # This test will ensure that we can parse router values successfully. Routers
  # can be provided as either an atom module name, or a router struct.
  test "parsing :router flags" do
    # grab a cache name
    name = Helper.create_name()

    # parse out valid router combinations
    {:ok, cache(router: router1)} = Cachex.Options.parse(name, [])

    {:ok, cache(router: router2)} =
      Cachex.Options.parse(name, router: Cachex.Router.Mod)

    # parse out invalid hook combinations
    {:error, msg} = Cachex.Options.parse(name, router: "[router]")
    {:error, ^msg} = Cachex.Options.parse(name, router: router(module: Missing))

    # check the router for the first state and the default value
    assert(router1 == router(module: Cachex.Router.Local))

    # check the router in the second state
    assert(router2 == router(module: Cachex.Router.Mod))

    # check the invalid router message
    assert(msg == :invalid_router)
  end

  # This test will verify the ability to record stats in a state. This option
  # will just add the Cachex Stats hook to the list of hooks inside the cache.
  # We just need to verify that the hook is added after being parsed.
  test "parsing :stats flags" do
    # grab a cache name
    name = Helper.create_name()

    # create a stats hook
    hook =
      hook(
        module: Cachex.Stats,
        name: name(name, :stats)
      )

    # parse the stats recording flags
    {:ok, cache(hooks: hooks)} = Cachex.Options.parse(name, stats: true)

    # ensure the stats hook has been added
    assert(hooks == hooks(pre: [], post: [hook]))
  end

  # This test will verify the parsing of transactions flags to determine whether
  # a cache has them enabled or disabled. This is simply checking whether the flag
  # is set to true or false, and the default. We also verify that the transaction
  # locksmith has its name set inside the returned state.
  test "parsing :transactions flags" do
    # grab a cache name
    name = Helper.create_name()

    # parse our values as options
    {:ok, cache(transactions: trans1)} =
      Cachex.Options.parse(name, transactions: true)

    {:ok, cache(transactions: trans2)} =
      Cachex.Options.parse(name, transactions: false)

    {:ok, cache(transactions: trans3)} = Cachex.Options.parse(name, [])

    # the first one should be truthy, and the latter two falsey
    assert trans1
    refute trans2
    refute trans3
  end

  test "parsing :warmers flags" do
    # grab a cache name
    name = Helper.create_name()

    # define our warmer to pass through to the cache
    Helper.create_warmer(:options_test_warmer, 50, fn _ ->
      :ignore
    end)

    # parse some warmers using the options parser
    results1 = Cachex.Options.parse(name, warmers: [])

    results2 =
      Cachex.Options.parse(name, warmers: warmer(module: :options_test_warmer))

    results3 =
      Cachex.Options.parse(name,
        warmers: [warmer(module: :options_test_warmer, name: :test)]
      )

    results4 = Cachex.Options.parse(name, warmers: ["warmer"])

    # the first three should all be valid
    {:ok, cache(warmers: warmers1)} = results1
    {:ok, cache(warmers: warmers2)} = results2
    {:ok, cache(warmers: warmers3)} = results3

    # and then we check the warmers...
    assert warmers1 == []
    assert warmers2 == [warmer(module: :options_test_warmer)]
    assert warmers3 == [warmer(module: :options_test_warmer, name: :test)]

    # the last one should be invalid
    assert results4 == {:error, :invalid_warmer}
  end

  # This test simply validates the ability to retrieve and transform an option
  # from inside a Keyword List. We validate both existing and missing options in
  # order to make sure there are no issues when retrieving. We also verify the
  # result of the call is the transformed result.
  test "transforming an option value in a Keyword List" do
    # define our list of options
    options = [key: "value"]

    # define a transformer
    transformer = &{&1}

    # transformer various options
    result1 = Cachex.Options.transform(options, :key, transformer)
    result2 = Cachex.Options.transform(options, :nah, transformer)

    # only the first should come back
    assert(result1 == {"value"})
    assert(result2 == {nil})
  end
end
