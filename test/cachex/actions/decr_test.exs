defmodule Cachex.Actions.DecrTest do
  use CachexCase

  # This test covers various combinations of decrementing cache items, by tweaking
  # the options provided alongside the calls. We validate the flags and values
  # coming back, as well as the fact they're forwarded to the hooks correctly.
  test "decrementing cache items" do
    # create a forwarding hook
    hook = ForwardHook.create()

    # create a test cache
    cache = Helper.create_cache([ hooks: [ hook ] ])

    # define write options
    opts1 = [ initial: 10 ]

    # decrement some items
    decr1 = Cachex.decr(cache, "key1")
    decr2 = Cachex.decr(cache, "key1", 2)
    decr3 = Cachex.decr(cache, "key2", 1, opts1)

    # the first result should be -1
    assert(decr1 == { :ok, -1 })

    # the second result should be -3
    assert(decr2 == { :ok, -3 })

    # the third result should be 9
    assert(decr3 == { :ok, 9 })

    # verify the hooks were updated with the decrement
    assert_receive({ { :decr, [ "key1", 1,     [] ] }, ^decr1 })
    assert_receive({ { :decr, [ "key1", 2,     [] ] }, ^decr2 })
    assert_receive({ { :decr, [ "key2", 1, ^opts1 ] }, ^decr3 })

    # retrieve all items
    value1 = Cachex.get(cache, "key1")
    value2 = Cachex.get(cache, "key2")

    # verify the items match
    assert(value1 == { :ok, -3 })
    assert(value2 == { :ok,  9 })
  end

  # This test covers the negative case where a value exists but is not an integer,
  # which naturally means we can't decrement it properly. We just check for an
  # error flag in this case.
  test "decrementing a non-numeric value" do
    # create a test cache
    cache = Helper.create_cache()

    # set a non-numeric value
    { :ok, true } = Cachex.put(cache, "key", "value")

    # try to increment the value
    result = Cachex.decr(cache, "key", 1)

    # we should receive an error
    assert(result == { :error, :non_numeric_value })
  end
end
