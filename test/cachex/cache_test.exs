defmodule Cachex.CacheTest do
  use CachexCase

  # Options parsing should add the cache name to the returned state, so this test
  # will just ensure that this is done correctly.
  test "adding a cache name to the state" do
    # grab a cache name
    name = Helper.create_name()

    # parse the options
    { :ok, state } = Cachex.Cache.create(name, [])

    # assert the name is added
    assert(state.name == name)
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
    fun1 = fn(_) -> [ 1, 2, 3 ] end
    fun2 = fn(_) -> [ 3, 2, 1 ] end

    # define valid command lists
    v_cmds1 = [ commands: [ ] ]
    v_cmds2 = [ commands:  [ lpop: command(type: :read, execute: fun1) ] ]
    v_cmds3 = [ commands: %{ lpop: command(type: :read, execute: fun1) } ]
    v_cmds4 = [ commands: [
      lpop: command(type:  :read, execute: fun1),
      lpop: command(type: :write, execute: fun2)
    ] ]

    # define invalid command lists
    i_cmds1 = [ commands: [ 1 ] ]
    i_cmds2 = [ commands: { 1 } ]
    i_cmds3 = [ commands: [ lpop: 1 ] ]

    # attempt to validate
    { :ok, results1 } = Cachex.Cache.create(name, v_cmds1)
    { :ok, results2 } = Cachex.Cache.create(name, v_cmds2)
    { :ok, results3 } = Cachex.Cache.create(name, v_cmds3)
    { :ok, results4 } = Cachex.Cache.create(name, v_cmds4)

    # the first two should be parsed into maps
    assert(results1.commands == %{ })
    assert(results2.commands == %{ lpop: command(type: :read, execute: fun1) })
    assert(results3.commands == %{ lpop: command(type: :read, execute: fun1) })

    # the fourth should keep only the first implementation
    assert(results4.commands == %{ lpop: command(type: :read, execute: fun1) })

    # parse the invalid lists
    { :error,  msg } = Cachex.Cache.create(name, i_cmds1)
    { :error, ^msg } = Cachex.Cache.create(name, i_cmds2)
    { :error, ^msg } = Cachex.Cache.create(name, i_cmds3)

    # should return an error
    assert(msg == :invalid_command)
  end

  # This test verifies the parsing of TTL related flags. We have to test various
  # combinations of :ttl_interval and :default_ttl to verify each state correctly.
  test "parsing :expiration flags" do
    # grab a cache name
    name = Helper.create_name()

    # parse out valid combinations
    { :ok, state1 } = Cachex.Cache.create(name, [ expiration: expiration(default: 1) ])
    { :ok, state2 } = Cachex.Cache.create(name, [ expiration: expiration(default: nil) ])
    { :ok, state3 } = Cachex.Cache.create(name, [ expiration: expiration(interval: 1) ])
    { :ok, state4 } = Cachex.Cache.create(name, [ expiration: expiration(interval: nil) ])
    { :ok, state5 } = Cachex.Cache.create(name, [ expiration: expiration(lazy: true) ])
    { :ok, state6 } = Cachex.Cache.create(name, [ expiration: expiration(lazy: false) ])
    { :ok, state7 } = Cachex.Cache.create(name, [ ])

    # verify all valid states parse correctly
    assert state1.expiration == expiration(default:   1, interval: 3000, lazy: true)
    assert state2.expiration == expiration(default: nil, interval: 3000, lazy: true)
    assert state3.expiration == expiration(default: nil, interval:    1, lazy: true)
    assert state4.expiration == expiration(default: nil, interval:  nil, lazy: true)
    assert state5.expiration == expiration(default: nil, interval: 3000, lazy: true)
    assert state6.expiration == expiration(default: nil, interval: 3000, lazy: false)
    assert state7.expiration == expiration(default: nil, interval: 3000, lazy: true)

    # parse out invalid combinations
    { :error,  msg } = Cachex.Cache.create(name, [ expiration: expiration(default: -1) ])
    { :error, ^msg } = Cachex.Cache.create(name, [ expiration: expiration(default: "1") ])
    { :error, ^msg } = Cachex.Cache.create(name, [ expiration: expiration(interval: -1) ])
    { :error, ^msg } = Cachex.Cache.create(name, [ expiration: expiration(interval: "1") ])
    { :error, ^msg } = Cachex.Cache.create(name, [ expiration: expiration(lazy: nil) ])
    { :error, ^msg } = Cachex.Cache.create(name, [ expiration: expiration(lazy: "1") ])
    { :error, ^msg } = Cachex.Cache.create(name, [ expiration: "expiration" ])

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
    fallback3 = fallback(default: &String.reverse/1, provide: {})
    fallback4 = fallback(provide: {})
    fallback5 = &String.reverse/1
    fallback6 = { }

    # parse all the valid fallbacks into caches
    { :ok, state1 } = Cachex.Cache.create(name, [ fallback: fallback1 ])
    { :ok, state2 } = Cachex.Cache.create(name, [ fallback: fallback2 ])
    { :ok, state3 } = Cachex.Cache.create(name, [ fallback: fallback3 ])
    { :ok, state4 } = Cachex.Cache.create(name, [ fallback: fallback4 ])
    { :ok, state5 } = Cachex.Cache.create(name, [ fallback: fallback5 ])
    { :error, msg } = Cachex.Cache.create(name, [ fallback: fallback6 ])

    # the first should use defaults
    assert(state1.fallback == fallback())

    # the second and fifth should have an action but no state
    assert(state2.fallback == fallback(default: &String.reverse/1))
    assert(state5.fallback == fallback(default: &String.reverse/1))

    # the third should have both an action and state
    assert(state3.fallback == fallback(default: &String.reverse/1, provide: {}))

    # the fourth should have a state but no action
    assert(state4.fallback == fallback(provide: {}))

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
    pre_hook = ForwardHook.create(type: :pre)

    # create our post hook
    post_hook = ForwardHook.create(type: :post)

    # parse out valid hook combinations
    { :ok, state1 } = Cachex.Cache.create(name, [ hooks: [ pre_hook, post_hook ] ])
    { :ok, state2 } = Cachex.Cache.create(name, [ hooks: pre_hook ])

    # parse out invalid hook combinations
    { :ok,  state3 } = Cachex.Cache.create(name, [ ])
    { :error,  msg } = Cachex.Cache.create(name, [ hooks: "[hooks]" ])
    { :error, ^msg } = Cachex.Cache.create(name, [ hooks: hook(module: Missing) ])

    # check the hook groupings for the first state
    assert(state1.hooks == hooks(pre: [ pre_hook ], post: [ post_hook ]))

    # check the hook groupings in the second state
    assert(state2.hooks == hooks(pre: [ pre_hook ], post: [ ]))

    # check the third state uses hook defaults
    assert(state3.hooks == hooks())

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
    { :ok, state1 } = Cachex.Cache.create(name, [ limit: max_size ])
    { :ok, state2 } = Cachex.Cache.create(name, [ limit: c_limits ])

    # parse options with invalid max_size
    { :ok, state3 } = Cachex.Cache.create(name, [ ])
           state4   = Cachex.Cache.create(name, [ limit: "max_size" ])

    # check the first and second states have limits
    assert(state1.limit == c_limits)
    assert(state2.limit == c_limits)
    assert(state1.hooks == hooks(pre: [], post: Cachex.Policy.LRW.hooks(c_limits)))
    assert(state2.hooks == hooks(pre: [], post: Cachex.Policy.LRW.hooks(c_limits)))

    # check the third has no limits attached
    assert(state3.limit == default)
    assert(state3.hooks == hooks(pre: [], post: []))

    # check the fourth causes an error
    assert(state4 == { :error, :invalid_limit })
  end

  # This test will verify the ability to record stats in a state. This option
  # will just add the Cachex Stats hook to the list of hooks inside the cache.
  # We just need to verify that the hook is added after being parsed.
  test "parsing :stats flags" do
    # grab a cache name
    name = Helper.create_name()

    # create a stats hook
    hook = hook(
      module: Cachex.Hook.Stats,
      options: [ name: name(name, :stats) ]
    )

    # parse the stats recording flags
    { :ok, state } = Cachex.Cache.create(name, [ stats: true ])

    # ensure the stats hook has been added
    assert(state.hooks == hooks(pre: [ ], post: [ hook ]))
  end

  # This test will verify the parsing of transactions flags to determine whether
  # a cache has them enabled or disabled. This is simply checking whether the flag
  # is set to true or false, and the default. We also verify that the transaction
  # locksmith has its name set inside the returned state.
  test "parsing :transactional flags" do
    # grab a cache name
    name = Helper.create_name()

    # parse our values as options
    { :ok, state1 } = Cachex.Cache.create(name, [ transactional:  true ])
    { :ok, state2 } = Cachex.Cache.create(name, [ transactional: false ])
    { :ok, state3 } = Cachex.Cache.create(name, [ ])

    # the first one should be truthy, and the latter two falsey
    assert(state1.transactional == true)
    assert(state2.transactional == false)
    assert(state3.transactional == false)
  end
end
