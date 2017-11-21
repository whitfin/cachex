defmodule Cachex.Actions.DecrTest do
  use CachexCase

  # This test covers various combinations of decrementing cache items, by tweaking
  # the options provided alongside the calls. We validate the flags and values
  # coming back, as well as the fact they're forwarded to the hooks correctly.
  test "decrementing cache items" do
    # create a forwarding hook
    hook = ForwardHook.create(%{ results: true })

    # create a test cache
    cache = Helper.create_cache([ hooks: [ hook ] ])

    # define write options
    opts1 = []
    opts2 = [  amount:  2 ]
    opts3 = [ initial: 10 ]
    opts4 = [ initial: 10, amount: 5 ]

    # decrement some items
    decr1 = Cachex.decr(cache, "key1", opts1)
    decr2 = Cachex.decr(cache, "key1", opts2)
    decr3 = Cachex.decr(cache, "key2", opts3)
    decr4 = Cachex.decr(cache, "key3", opts4)

    # the first result should be -1
    assert(decr1 == { :missing, -1 })

    # the second result should be -3
    assert(decr2 == { :ok, -3 })

    # the third result should be 9
    assert(decr3 == { :missing, 9 })

    # the fourth result should be 5
    assert(decr4 == { :missing, 5 })

    # verify the hooks were updated with the decrement
    assert_receive({ { :decr, [ "key1", ^opts1 ] }, ^decr1 })
    assert_receive({ { :decr, [ "key1", ^opts2 ] }, ^decr2 })
    assert_receive({ { :decr, [ "key2", ^opts3 ] }, ^decr3 })
    assert_receive({ { :decr, [ "key3", ^opts4 ] }, ^decr4 })

    # retrieve all items
    value1 = Cachex.get(cache, "key1")
    value2 = Cachex.get(cache, "key2")
    value3 = Cachex.get(cache, "key3")

    # verify the items match
    assert(value1 == { :ok, -3 })
    assert(value2 == { :ok,  9 })
    assert(value3 == { :ok,  5 })
  end

  # This test covers the negative case where a value exists but is not an integer,
  # which naturally means we can't decrement it properly. We just check for an
  # error flag in this case.
  test "decrementing a non-numeric value" do
    # create a test cache
    cache = Helper.create_cache()

    # set a non-numeric value
    { :ok, true } = Cachex.set(cache, "key", "value")

    # try to increment the value
    result = Cachex.decr(cache, "key")

    # we should receive an error
    assert(result == { :error, :non_numeric_value })
  end

end
