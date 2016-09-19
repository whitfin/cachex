defmodule Cachex.OptionsTest do
  use CachexCase

  # Options parsing should add the cache name to the returned state, so this test
  # will just ensure that this is done correctly.
  test "adding a cache name to the state" do
    # grab a cache name
    name = Helper.create_name()

    # parse the options
    { :ok, state } = Cachex.Options.parse(name, [])

    # assert the name is added
    assert(state.cache == name)
  end

  # On-Demand expiration can be disabled, and so we have to parse out whether the
  # user has chosen to disable it or not. This is simply checking for a truthy
  # value provided aginst disabling the expiration.
  test "parsing :disable_ode flags" do
    # grab a cache name
    name = Helper.create_name()

    # parse our values as options
    { :ok, state1 } = Cachex.Options.parse(name, [ disable_ode:  true ])
    { :ok, state2 } = Cachex.Options.parse(name, [ disable_ode: false ])
    { :ok, state3 } = Cachex.Options.parse(name, [ ])

    # the first one should be truthy, and the latter two falsey
    assert(state1.disable_ode == true)
    assert(state2.disable_ode == false)
    assert(state3.disable_ode == false)
  end

  # This test ensures that custom ETS options can be passed through to the ETS
  # table. We need to check that if the value is not a list, we use defaults. We
  # also verify that read/write concurrency is true unless explicitly disabled.
  test "parsing :ets_opts flags" do
    # grab a cache name
    name = Helper.create_name()

    # define the defaults
    defaults = [
      read_concurrency: true,
      write_concurrency: true
    ]

    # parse out valid options
    { :ok, state1 } = Cachex.Options.parse(name, [ ets_opts: [ :compressed ] ])

    # parse out invalid options
    { :ok, state2 } = Cachex.Options.parse(name, [ ets_opts: "[:compressed]" ])
    { :ok, state3 } = Cachex.Options.parse(name, [ ])

    # parse out overridden options
    { :ok, state4 } = Cachex.Options.parse(name, [
      ets_opts: [
        read_concurrency: false,
        write_concurrency: false
      ]
    ])

    # the first options are completely valid
    assert(state1.ets_opts == defaults ++ [ :compressed ])

    # both the second and third options use defaults
    assert(state2.ets_opts == defaults)
    assert(state3.ets_opts == defaults)

    # the fourth options overrides the concurrency options
    assert(state4.ets_opts == [
      read_concurrency: false,
      write_concurrency: false
    ])
  end

  # Every cache can have a default fallback implementation which is used in case
  # of no fallback provided against cache reads. The only constraint here is that
  # the provided value is a valid function (of any arity).
  test "parsing :fallback flags" do
    # grab a cache name
    name = Helper.create_name()

    # define our fallbacks
    valid_fb   = &(&1)
    invalid_fb = "nop"

    # parse both as options
    { :ok, state1 } = Cachex.Options.parse(name, [ fallback:   valid_fb ])
    { :ok, state2 } = Cachex.Options.parse(name, [ fallback: invalid_fb ])

    # the first should have parsed
    assert(state1.fallback == valid_fb)

    # but the second should be nil
    assert(state2.fallback == nil)
  end

  # This test will ensure that fallback arguments can be passed as options. We
  # only accept a list of arguments, anything else should be defaulted to an empty
  # list of arguments (to avoid having to check later in the execution flow).
  test "parsing :fallback_args flags" do
    # grab a cache name
    name = Helper.create_name()

    # parse out valid arguments
    { :ok, state1 } = Cachex.Options.parse(name, [ fallback_args: [ 1, 2, 3 ] ])

    # parse out invalid arguments
    { :ok, state2 } = Cachex.Options.parse(name, [ fallback_args: "[1, 2, 3]" ])
    { :ok, state3 } = Cachex.Options.parse(name, [ ])

    # assert the first arguments are valid
    assert(state1.fallback_args == [ 1, 2, 3 ])

    # both the second and third options use defaults
    assert(state2.fallback_args == [])
    assert(state3.fallback_args == [])
  end

  # This test will ensure that we can parse Hook values successfully. Hooks can
  # be provided as either a List or a single Hook. We also need to check that
  # Hooks are grouped into the correct pre/post groups inside the State.
  test "parsing :hooks flags" do
    # grab a cache name
    name = Helper.create_name()

    # create our pre hook
    pre_hook = ForwardHook.create(%{
      type: :pre
    })

    # create our post hook
    post_hook = ForwardHook.create(%{
      type: :post
    })

    # parse out valid hook combinations
    { :ok, state1 } = Cachex.Options.parse(name, [ hooks: [ pre_hook, post_hook ] ])
    { :ok, state2 } = Cachex.Options.parse(name, [ hooks: pre_hook ])

    # parse out invalid hook combinations
    { :ok, state3 } = Cachex.Options.parse(name, [ hooks: "[hooks]" ])
    { :ok, state4 } = Cachex.Options.parse(name, [ ])
    { :error, msg } = Cachex.Options.parse(name, [ hooks: %Cachex.Hook{ module: Missing }])

    # check the hook groupings for the first state
    assert(state1.pre_hooks == [ pre_hook ])
    assert(state1.post_hooks == [ post_hook ])

    # check the hook groupings in the second state
    assert(state2.pre_hooks == [ pre_hook ])
    assert(state2.post_hooks == [ ])

    # check the third and fourth states use pre_hook defaults
    assert(state3.pre_hooks == [ ])
    assert(state4.pre_hooks == [ ])

    # check the third and fourth states use post_hook defaults
    assert(state3.post_hooks == [ ])
    assert(state4.post_hooks == [ ])

    # check the fifth state returns an error
    assert(msg == :invalid_hook)
  end

  # This test ensures that the max size options can be correctly parsed. Parsing
  # this flag will set the Limit field inside the returned State, so it needs to
  # be checked. It will also add any Limit hooks to the hooks list, so this needs
  # to also be verified within this test.
  test "parsing :limit flags" do
    # grab a cache name
    name = Helper.create_name()

    # create a default limit
    default = %Cachex.Limit{ }

    # our cache limit
    max_size = 500
    c_limits = %Cachex.Limit{ limit: max_size }

    # parse options with a valid max_size
    { :ok, state1 } = Cachex.Options.parse(name, [ limit: max_size ])
    { :ok, state2 } = Cachex.Options.parse(name, [ limit: c_limits ])

    # parse options with invalid max_size
    { :ok, state3 } = Cachex.Options.parse(name, [ limit: "max_size" ])
    { :ok, state4 } = Cachex.Options.parse(name, [ ])

    # check the first and second states have limits
    assert(state1.limit == c_limits)
    assert(state2.limit == c_limits)
    assert(state1.post_hooks == Cachex.Limit.to_hooks(c_limits))
    assert(state2.post_hooks == Cachex.Limit.to_hooks(c_limits))

    # check the third and fourth states have no limits
    assert(state3.limit == default)
    assert(state4.limit == default)
    assert(state3.post_hooks == [])
    assert(state4.post_hooks == [])
  end

  # This test will verify the ability to record stats in a State. This option
  # will just add the Cachex Stats hook to the list of hooks inside the cache.
  # We just need to verify that the hook is added after being parsed.
  test "parsing :record_stats flags" do
    # grab a cache name
    name = Helper.create_name()

    # create a stats hook
    hook = %Cachex.Hook{
      module: Cachex.Hook.Stats,
      server_args: [ name: Cachex.Util.Names.stats(name) ]
    }

    # parse the record_stats flags
    { :ok, state } = Cachex.Options.parse(name, [ record_stats: true ])

    # ensure the stats hook has been added
    assert(state.pre_hooks == [ ])
    assert(state.post_hooks == [ hook ])
  end

  # This test will verify the parsing of transactions flags to determine whether
  # a cache has them enabled or disabled. This is simply checking whether the flag
  # is set to true or false, and the default. We also verify that the transaction
  # manager has its name set inside the returned state.
  test "parsing :transactions flags" do
    # grab a cache name
    name = Helper.create_name()

    # parse our values as options
    { :ok, state1 } = Cachex.Options.parse(name, [ transactions:  true ])
    { :ok, state2 } = Cachex.Options.parse(name, [ transactions: false ])
    { :ok, state3 } = Cachex.Options.parse(name, [ ])

    # the first one should be truthy, and the latter two falsey
    assert(state1.transactions == true)
    assert(state2.transactions == false)
    assert(state3.transactions == false)

    # we also need to make sure they all have the manager name
    assert(state1.manager == Cachex.Util.Names.manager(name))
    assert(state2.manager == Cachex.Util.Names.manager(name))
    assert(state3.manager == Cachex.Util.Names.manager(name))
  end

  # This test verifies the parsing of TTL related flags. We have to test various
  # combinations of :ttl_interval and :default_ttl to verify each state correctly.
  test "parsing :ttl_interval flags" do
    # grab a cache name
    name = Helper.create_name()

    # parse out valid combinations
    { :ok, state1 } = Cachex.Options.parse(name, [ default_ttl: 1 ])
    { :ok, state2 } = Cachex.Options.parse(name, [ default_ttl: 1, ttl_interval: -1 ])
    { :ok, state3 } = Cachex.Options.parse(name, [ default_ttl: 1, ttl_interval: 500 ])
    { :ok, state4 } = Cachex.Options.parse(name, [ ttl_interval: 500 ])

    # parse out invalid combinations
    { :ok, state5 } = Cachex.Options.parse(name, [ default_ttl: "1" ])
    { :ok, state6 } = Cachex.Options.parse(name, [ default_ttl: -1 ])
    { :ok, state7 } = Cachex.Options.parse(name, [ ttl_interval: "1" ])
    { :ok, state8 } = Cachex.Options.parse(name, [ ttl_interval: -1 ])

    # the first state should have a default_ttl of 1 and a default ttl_interval
    assert(state1.default_ttl == 1)
    assert(state1.ttl_interval == 3000)

    # the second state should have default_ttl 1 and ttl_interval disabled
    assert(state2.default_ttl == 1)
    assert(state2.ttl_interval == nil)

    # the third state should have default_ttl of 1 and ttl_interval of 500
    assert(state3.default_ttl == 1)
    assert(state3.ttl_interval == 500)

    # the fourth state should have default_ttl disabled and ttl_interval of 500
    assert(state4.default_ttl == nil)
    assert(state4.ttl_interval == 500)

    # the fifth state should have both disabled
    assert(state5.default_ttl == nil)
    assert(state5.ttl_interval == nil)

    # the sixth state should have both disabled
    assert(state6.default_ttl == nil)
    assert(state6.ttl_interval == nil)

    # the seventh state should have both disabled
    assert(state7.default_ttl == nil)
    assert(state7.ttl_interval == nil)

    # the eight state should have both disabled
    assert(state8.default_ttl == nil)
    assert(state8.ttl_interval == nil)
  end

  # If we don't receive a valid list to parse options from, we just default to
  # returning an empty state with only the cache name set. This test just checks
  # that parsing an invalid list is the same as parsing an empty list.
  test "parsing without a valid options list" do
    # grab a cache name
    name = Helper.create_name()

    # parse both valid and invalid options
    { :ok, state1 } = Cachex.Options.parse(name, [ ])
    { :ok, state2 } = Cachex.Options.parse(name, "invalid_options")

    # assert the two caches match
    assert(state1 == state2)
  end

end
