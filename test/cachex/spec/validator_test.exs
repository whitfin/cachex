defmodule Cachex.Spec.ValidatorTest do
  use CachexCase

  alias Cachex.Spec.Validator

  # Bind any required hooks for test execution
  setup_all do
    # bind the required hooks for testing
    ForwardHook.bind(
      validator_hook_pre: [type: :pre],
      validator_hook_post: [type: :post],
      validator_hook_timeout: [timeout: 100],
      validator_hook_actions: [actions: [:get]],
      validator_invalid_hook_actions: [actions: "true"],
      validator_invalid_hook_async: [async: "true"],
      validator_invalid_hook_provisions: [provisions: nil],
      validator_invalid_hook_timeout: [timeout: " "],
      validator_invalid_hook_timeout_negative: [timeout: -1],
      validator_invalid_hook_type: [type: :missing]
    )

    :ok
  end

  test "validation of command records" do
    # define some valid records
    command1 = command(type: :read, execute: &String.reverse/1)
    command2 = command(type: :write, execute: &String.reverse/1)

    # ensure all records are valid
    assert Validator.valid?(:command, command1)
    assert Validator.valid?(:command, command2)

    # define some invalid records
    command3 = command(type: :invalid, execute: &String.reverse/1)
    command4 = command(type: :write, execute: &is_function/2)

    # ensure all records are invalid
    refute Validator.valid?(:command, command3)
    refute Validator.valid?(:command, command4)
  end

  test "validation of entry records" do
    # define some valid records
    entry1 = entry(key: "key", touched: 1, ttl: nil, value: "value")
    entry2 = entry(key: "key", touched: 1, ttl: 1, value: "value")
    entry3 = entry(key: "key", touched: 1, ttl: nil, value: nil)
    entry4 = entry(key: nil, touched: 1, ttl: nil, value: nil)

    # ensure all records are valid
    assert Validator.valid?(:entry, entry1)
    assert Validator.valid?(:entry, entry2)
    assert Validator.valid?(:entry, entry3)
    assert Validator.valid?(:entry, entry4)

    # define some invalid records
    entry5 = entry(key: "key", touched: nil, ttl: nil, value: nil)
    entry6 = entry(key: "key", touched: " ", ttl: nil, value: nil)
    entry7 = entry(key: "key", touched: -1, ttl: nil, value: nil)
    entry8 = entry(key: "key", touched: 1, ttl: " ", value: nil)
    entry9 = entry(key: "key", touched: 1, ttl: -1, value: nil)

    # ensure all records are invalid
    refute Validator.valid?(:entry, entry5)
    refute Validator.valid?(:entry, entry6)
    refute Validator.valid?(:entry, entry7)
    refute Validator.valid?(:entry, entry8)
    refute Validator.valid?(:entry, entry9)
  end

  test "validation of expiration records" do
    # define some valid records
    expiration1 = expiration(default: nil, interval: nil, lazy: true)
    expiration2 = expiration(default: nil, interval: 100, lazy: true)
    expiration3 = expiration(default: 100, interval: nil, lazy: true)

    # ensure all records are valid
    assert Validator.valid?(:expiration, expiration1)
    assert Validator.valid?(:expiration, expiration2)
    assert Validator.valid?(:expiration, expiration3)

    # define some invalid records
    expiration4 = expiration(default: nil, interval: nil, lazy: "false")
    expiration5 = expiration(default: nil, interval: " ", lazy: false)
    expiration6 = expiration(default: " ", interval: nil, lazy: false)
    expiration7 = expiration(default: nil, interval: -1, lazy: false)
    expiration8 = expiration(default: -1, interval: nil, lazy: false)

    # ensure all records are invalid
    refute Validator.valid?(:expiration, expiration4)
    refute Validator.valid?(:expiration, expiration5)
    refute Validator.valid?(:expiration, expiration6)
    refute Validator.valid?(:expiration, expiration7)
    refute Validator.valid?(:expiration, expiration8)
  end

  test "validation of fallback records" do
    # define some valid records
    fallback1 = fallback(default: nil, state: nil)
    fallback2 = fallback(default: nil, state: " ")
    fallback3 = fallback(default: fn _ -> nil end, state: nil)
    fallback4 = fallback(default: fn _, _ -> nil end, state: nil)

    # ensure all records are valid
    assert Validator.valid?(:fallback, fallback1)
    assert Validator.valid?(:fallback, fallback2)
    assert Validator.valid?(:fallback, fallback3)
    assert Validator.valid?(:fallback, fallback4)

    # define some invalid records
    fallback5 = fallback(default: " ", state: nil)
    fallback6 = fallback(default: fn -> nil end, state: nil)

    # ensure all records are invalid
    refute Validator.valid?(:fallback, fallback5)
    refute Validator.valid?(:fallback, fallback6)
  end

  test "validation of hook records" do
    # define some valid records
    hook1 = hook(module: :validator_hook_pre)
    hook2 = hook(module: :validator_hook_post)
    hook3 = hook(module: :validator_hook_timeout)
    hook4 = hook(module: :validator_hook_actions)

    # ensure all records are valid
    assert Validator.valid?(:hook, hook1)
    assert Validator.valid?(:hook, hook2)
    assert Validator.valid?(:hook, hook3)
    assert Validator.valid?(:hook, hook4)

    # define some invalid records
    hook5 = hook(name: " ")
    hook6 = hook(module: :missing)
    hook7 = hook(module: :validator_invalid_hook_actions)
    hook8 = hook(module: :validator_invalid_hook_async)
    hook9 = hook(module: :validator_invalid_hook_provisions)
    hook10 = hook(module: :validator_invalid_hook_timeout)
    hook11 = hook(module: :validator_invalid_hook_timeout_negative)
    hook12 = hook(module: :validator_invalid_hook_type)

    # ensure all records are invalid
    refute Validator.valid?(:hook, hook5)
    refute Validator.valid?(:hook, hook6)
    refute Validator.valid?(:hook, hook7)
    refute Validator.valid?(:hook, hook8)
    refute Validator.valid?(:hook, hook9)
    refute Validator.valid?(:hook, hook10)
    refute Validator.valid?(:hook, hook11)
    refute Validator.valid?(:hook, hook12)
  end

  test "validation of hooks records" do
    # define some valid records
    hooks1 = hooks(pre: [], post: [])
    hooks2 = hooks(pre: [hook(module: :validator_hook_pre)], post: [])
    hooks3 = hooks(pre: [], post: [hook(module: :validator_hook_post)])

    # ensure all records are valid
    assert Validator.valid?(:hooks, hooks1)
    assert Validator.valid?(:hooks, hooks2)
    assert Validator.valid?(:hooks, hooks3)

    # define some invalid records
    hooks4 = hooks(pre: ["test"], post: [])
    hooks5 = hooks(pre: [], post: ["test"])
    hooks6 = hooks(pre: [1], post: [])
    hooks7 = hooks(pre: [], post: [1])
    hooks8 = hooks(pre: [hook()], post: [hook()])
    hooks9 = hooks(pre: "test", post: [])
    hooks10 = hooks(pre: [], post: "test")

    # ensure all records are invalid
    refute Validator.valid?(:hooks, hooks4)
    refute Validator.valid?(:hooks, hooks5)
    refute Validator.valid?(:hooks, hooks6)
    refute Validator.valid?(:hooks, hooks7)
    refute Validator.valid?(:hooks, hooks8)
    refute Validator.valid?(:hooks, hooks9)
    refute Validator.valid?(:hooks, hooks10)
  end

  test "validation of limit records" do
    # define some valid records
    limit1 = limit(size: 100)
    limit2 = limit(size: nil)

    # ensure all records are valid
    assert Validator.valid?(:limit, limit1)
    assert Validator.valid?(:limit, limit2)

    # define some invalid records
    limit3 = limit(size: -1)
    limit4 = limit(policy: :missing)
    limit5 = limit(reclaim: 0.0)
    limit6 = limit(reclaim: 1.1)
    limit7 = limit(options: nil)
    limit8 = limit(options: [1])

    # ensure all records are invalid
    refute Validator.valid?(:limit, limit3)
    refute Validator.valid?(:limit, limit4)
    refute Validator.valid?(:limit, limit5)
    refute Validator.valid?(:limit, limit6)
    refute Validator.valid?(:limit, limit7)
    refute Validator.valid?(:limit, limit8)
  end

  test "validation of warmer records" do
    # create a warmer for validation
    Helper.create_warmer(:validator_warmer, 1000, fn _ ->
      :ignore
    end)

    # define some records
    warmer1 = warmer(module: :validator_warmer)
    warmer2 = warmer(module: __MODULE__)
    warmer3 = warmer(module: :missing)

    # ensure the first is valid
    assert Validator.valid?(:warmer, warmer1)

    # the others are all invalid
    refute Validator.valid?(:warmer, warmer2)
    refute Validator.valid?(:warmer, warmer3)
  end
end
