defmodule Cachex.Actions.IncrTest do
  use CachexCase

  # This test covers various combinations of incrementing cache items, by tweaking
  # the options provided alongside the calls. We validate the flags and values
  # coming back, as well as the fact they're forwarded to the hooks correctly.
  test "incrementing cache items" do
    # create a forwarding hook
    hook = ForwardHook.create(%{ results: true })

    # create a test cache
    cache = Helper.create_cache([ hooks: [ hook ] ])

    # define write options
    opts1 = []
    opts2 = [ amount: 2 ]
    opts3 = [ initial: 10 ]
    opts4 = [ initial: 10, amount: 5 ]

    # increment some items
    incr1 = Cachex.incr(cache, "key1", opts1)
    incr2 = Cachex.incr(cache, "key1", opts2)
    incr3 = Cachex.incr(cache, "key2", opts3)
    incr4 = Cachex.incr(cache, "key3", opts4)

    # the first result should be 1
    assert(incr1 == { :missing, 1 })

    # the second result should be 3
    assert(incr2 == { :ok, 3 })

    # the third result should be 11
    assert(incr3 == { :missing, 11 })

    # the fourth result should be 15
    assert(incr4 == { :missing, 15 })

    # verify the hooks were updated with the increment
    assert_receive({ { :incr, [ "key1", ^opts1 ] }, ^incr1 })
    assert_receive({ { :incr, [ "key1", ^opts2 ] }, ^incr2 })
    assert_receive({ { :incr, [ "key2", ^opts3 ] }, ^incr3 })
    assert_receive({ { :incr, [ "key3", ^opts4 ] }, ^incr4 })

    # retrieve all items
    value1 = Cachex.get(cache, "key1")
    value2 = Cachex.get(cache, "key2")
    value3 = Cachex.get(cache, "key3")

    # verify the items match
    assert(value1 == { :ok,  3 })
    assert(value2 == { :ok, 11 })
    assert(value3 == { :ok, 15 })
  end

  # This test covers the negative case where a value exists but is not an integer,
  # which naturally means we can't increment it properly. We just check for an
  # error flag in this case.
  test "incrementing a non-numeric value" do
    # create a test cache
    cache = Helper.create_cache()

    # set a non-numeric value
    { :ok, true } = Cachex.set(cache, "key", "value")

    # try to increment the value
    result = Cachex.incr(cache, "key")

    # we should receive an error
    assert(result == { :error, :non_numeric_value })
  end

end
