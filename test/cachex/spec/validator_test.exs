defmodule Cachex.Spec.ValidatorTest do
  use CachexCase

  alias Cachex.Spec.Validator

  test "validation of entry records" do
    # define some valid records
    entry1 = entry(key: "key", touched: 1, ttl: nil, value: "value")
    entry2 = entry(key: "key", touched: 1, ttl:   1, value: "value")
    entry3 = entry(key: "key", touched: 1, ttl: nil, value: nil)
    entry4 = entry(key:   nil, touched: 1, ttl: nil, value: nil)

    # ensure all records are valid
    assert Validator.valid?(entry1)
    assert Validator.valid?(entry2)
    assert Validator.valid?(entry3)
    assert Validator.valid?(entry4)

    # define some invalid records
    entry5 = entry(key: "key", touched: nil, ttl: nil, value: nil)
    entry6 = entry(key: "key", touched: " ", ttl: nil, value: nil)
    entry7 = entry(key: "key", touched:  -1, ttl: nil, value: nil)
    entry8 = entry(key: "key", touched:   1, ttl: " ", value: nil)
    entry9 = entry(key: "key", touched:   1, ttl:  -1, value: nil)

    # ensure all records are invalid
    refute Validator.valid?(entry5)
    refute Validator.valid?(entry6)
    refute Validator.valid?(entry7)
    refute Validator.valid?(entry8)
    refute Validator.valid?(entry9)
  end

  test "validation of expiration records" do
    # define some valid records
    expiration1 = expiration(default: nil, interval: nil, lazy: true)
    expiration2 = expiration(default: nil, interval: 100, lazy: true)
    expiration3 = expiration(default: 100, interval: nil, lazy: true)

    # ensure all records are valid
    assert Validator.valid?(expiration1)
    assert Validator.valid?(expiration2)
    assert Validator.valid?(expiration3)

    # define some invalid records
    expiration4 = expiration(default: nil, interval: nil, lazy: "false")
    expiration5 = expiration(default: nil, interval: " ", lazy: false)
    expiration6 = expiration(default: " ", interval: nil, lazy: false)
    expiration7 = expiration(default: nil, interval:  -1, lazy: false)
    expiration8 = expiration(default:  -1, interval: nil, lazy: false)

    # ensure all records are invalid
    refute Validator.valid?(expiration4)
    refute Validator.valid?(expiration5)
    refute Validator.valid?(expiration6)
    refute Validator.valid?(expiration7)
    refute Validator.valid?(expiration8)
  end

  test "validation of fallback records" do
    # define some valid records
    fallback1 = fallback(default: nil, provide: nil)
    fallback2 = fallback(default: nil, provide: " ")
    fallback3 = fallback(default: fn _ -> nil end, provide: nil)
    fallback4 = fallback(default: fn _, _ -> nil end, provide: nil)

    # ensure all records are valid
    assert Validator.valid?(fallback1)
    assert Validator.valid?(fallback2)
    assert Validator.valid?(fallback3)
    assert Validator.valid?(fallback4)

    # define some invalid records
    fallback5 = fallback(default: " ", provide: nil)
    fallback6 = fallback(default: fn -> nil end, provide: nil)

    # ensure all records are invalid
    refute Validator.valid?(fallback5)
    refute Validator.valid?(fallback6)
  end

  test "validation of hook records" do
    # define some valid records
    hook1 = hook(module: __MODULE__, ref:    nil, timeout: nil, type:  :pre)
    hook2 = hook(module: __MODULE__, ref:    nil, timeout: nil, type: :post)
    hook3 = hook(module: __MODULE__, ref:    nil, timeout: 100, type:  :pre)
    hook4 = hook(module: __MODULE__, ref: self(), timeout: 100, type:  :pre)

    # ensure all records are valid
    assert Validator.valid?(hook1)
    assert Validator.valid?(hook2)
    assert Validator.valid?(hook3)
    assert Validator.valid?(hook4)

    # define some invalid records
    hook5  = hook(module: :missing)
    hook6  = hook(module: __MODULE__, async: "true")
    hook7  = hook(module: __MODULE__, options: nil)
    hook8  = hook(module: __MODULE__, options: [1])
    hook9  = hook(module: __MODULE__, provide: nil)
    hook10 = hook(module: __MODULE__, ref: " ")
    hook11 = hook(module: __MODULE__, timeout: -1)
    hook12 = hook(module: __MODULE__, timeout: " ")
    hook13 = hook(module: __MODULE__, type: " ")
    hook14 = hook(module: __MODULE__, type: :missing)

    # ensure all records are invalid
    refute Validator.valid?(hook5)
    refute Validator.valid?(hook6)
    refute Validator.valid?(hook7)
    refute Validator.valid?(hook8)
    refute Validator.valid?(hook9)
    refute Validator.valid?(hook10)
    refute Validator.valid?(hook11)
    refute Validator.valid?(hook12)
    refute Validator.valid?(hook13)
    refute Validator.valid?(hook14)
  end

  test "validation of hooks records" do
    # define some valid records
    hooks1 = hooks(pre: [], post: [])
    hooks2 = hooks(pre: [hook(module: __MODULE__)], post: [])
    hooks3 = hooks(pre: [], post: [hook(module: __MODULE__)])

    # ensure all records are valid
    assert Validator.valid?(hooks1)
    assert Validator.valid?(hooks2)
    assert Validator.valid?(hooks3)

    # define some invalid records
    hooks4 = hooks(pre: [ "test" ], post: [ ])
    hooks5 = hooks(pre: [ ], post: [ "test" ])
    hooks6 = hooks(pre: [1], post: [ ])
    hooks7 = hooks(pre: [ ], post: [1])
    hooks8 = hooks(pre: [ hook() ], post: [ hook() ])

    # ensure all records are invalid
    refute Validator.valid?(hooks4)
    refute Validator.valid?(hooks5)
    refute Validator.valid?(hooks6)
    refute Validator.valid?(hooks7)
    refute Validator.valid?(hooks8)
  end

  test "validation of limit records" do
    # define some valid records
    limit1 = limit(size: 100)
    limit2 = limit(size: nil)

    # ensure all records are valid
    assert Validator.valid?(limit1)
    assert Validator.valid?(limit2)

    # define some invalid records
    limit3 = limit(size:  -1)
    limit4 = limit(policy: :missing)
    limit5 = limit(reclaim: 0.0)
    limit6 = limit(reclaim: 1.1)
    limit7 = limit(options: nil)
    limit8 = limit(options: [1])

    # ensure all records are invalid
    refute Validator.valid?(limit3)
    refute Validator.valid?(limit4)
    refute Validator.valid?(limit5)
    refute Validator.valid?(limit6)
    refute Validator.valid?(limit7)
    refute Validator.valid?(limit8)
  end
end
