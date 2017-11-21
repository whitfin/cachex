defmodule Cachex.UtilTest do
  use CachexCase

  # This test ensures that we have an appropriate result when convering a number
  # of bytes to a human readable format. The function can recursively handle any
  # magnitude up to a TiB, so we need to make sure we test each level. Note that
  # all results are expected to be two decimal places (even if .00).
  test "converting bytes to a readable format" do
    # our magic numbers
    bibs = 512
    kibs = bibs * 512
    mibs = kibs * 512
    gibs = mibs * 512
    tibs = gibs * 512
    pibs = tibs * 512

    # our conversions
    bibs_bin = Cachex.Util.bytes_to_readable(bibs)
    kibs_bin = Cachex.Util.bytes_to_readable(kibs)
    mibs_bin = Cachex.Util.bytes_to_readable(mibs)
    gibs_bin = Cachex.Util.bytes_to_readable(gibs)
    tibs_bin = Cachex.Util.bytes_to_readable(tibs)
    pibs_bin = Cachex.Util.bytes_to_readable(pibs)

    # assertions
    assert(bibs_bin == "512.00 B")
    assert(kibs_bin == "256.00 KiB")
    assert(mibs_bin == "128.00 MiB")
    assert(gibs_bin == "64.00 GiB")
    assert(tibs_bin == "32.00 TiB")
    assert(pibs_bin == "16384.00 TiB")
  end

  # Match statements are heavily used, so we need to make sure they all compile
  # correctly when called in the utilities. There are several cases to cover here,
  # including those with and without field aliases (for example using :key instead)
  # of $1. We also need to ensure that where clauses get wrapped, but never doubly.
  test "creating match statements" do
    # create our returns, with and without indexes
    return1 = { { :"$1", :"$2" } }
    return2 = { { :key, :touched, :ttl, :value } }

    # create our returns, with and without indexes, and with and without lists
    where1 = [ { :"/=", :"$3", nil } ]
    where2 =    { :"/=", :ttl, nil }

    # compile our matches
    match1 = Cachex.Util.create_match(return1, where1)
    match2 = Cachex.Util.create_match(return2, where2)

    # compare match1 to hand written
    assert(match1 == [
      {
        { :_, :"$1", :"$2", :"$3", :"$4" },
        [ { :"/=", :"$3", nil } ],
        [ { { :"$1", :"$2" } } ]
      }
    ])

    # compare match2 to hand written
    assert(match2 == [
      {
        { :_, :"$1", :"$2", :"$3", :"$4" },
        [ { :"/=", :"$3", nil } ],
        [ { { :"$1", :"$2", :"$3", :"$4" } } ]
      }
    ])
  end

  # This test ensures the integrity of the basic option parser provided for use
  # when parsing cache options. We need to test the ability to retrieve a value
  # based on a condition, but also returning default values in case of condition
  # failure or error.
  test "getting options from a Keyword List" do
    # our base option set
    options = [ positive: 10, negative: -10 ]

    # our base condition
    condition = &(is_number(&1) and &1 > 0)

    # parse out using a true condition
    result1 = Cachex.Util.get_opt(options, :positive, condition)

    # parse out using a false condition (should return a default)
    result2 = Cachex.Util.get_opt(options, :negative, condition)

    # parse out using an error condition (should return a custom default)
    result3 = Cachex.Util.get_opt(options, :negative, fn(_) ->
      raise ArgumentError
    end, 0)

    # condition true means we return the value
    assert(result1 == 10)

    # condition false and no default means we return nil
    assert(result2 == nil)

    # condition false with a default returns the default
    assert(result3 == 0)
  end

  # We have a common utility to check whether a TTL has passed or not based on
  # an input of a write time and a TTL length. This test ensures that this returns
  # true or false based on whether we should expire or not. There's also additional
  # logic that a cache can have expiration disabled, and so if we pass a state with
  # it disabled, it should return false regardless of the date deltas.
  test "has_expired? checking whether an expiration has passed" do
    # this combination has expired
    touched1 = 5000
    time_tl1 = 5000

    # this combination has not
    touched2 = :os.system_time(:milli_seconds)
    time_tl2 = 100_000_000

    # define both an enabled and disabled state
    state1 = %Cachex.Cache{ ode: true }
    state2 = %Cachex.Cache{ state1 | ode: false }

    # expired combination regardless of state
    result1 = Cachex.Util.has_expired?(touched1, time_tl1)

    # unexpired combination regardless of state
    result2 = Cachex.Util.has_expired?(touched2, time_tl2)

    # expired combination with state enabled
    result3 = Cachex.Util.has_expired?(state1, touched1, time_tl1)

    # expired combination with state disabled
    result4 = Cachex.Util.has_expired?(state2, touched1, time_tl1)

    # only the first and third should have expired
    assert(result1)
    assert(result3)

    # the second and fourth should not have
    refute(result2)
    refute(result4)
  end

  # There are a couple of places we want to increment a value inside a Map without
  # having to re-roll it, so it lives inside the Utils. This test just ensures that
  # we can both increment numeric values, or overwrite a non-numeric value with the
  # value we're trying to increment with.
  test "incrementing a value inside a Map" do
    # define our base map
    map = %{ "key1" => 1, "key2" => "1" }

    # attempt to increment a numberic value
    result1 = Cachex.Util.increment_map_key(map, "key1", 1)

    # attempt to increment a non-numeric value (overwrites)
    result2 = Cachex.Util.increment_map_key(map, "key2", 1)

    # attempt to increment a missing value (sets)
    result3 = Cachex.Util.increment_map_key(map, "key3", 1)

    # the first result should have incremented
    assert(result1 == %{ "key1" => 2, "key2" => "1" })

    # the second result should have overwritten
    assert(result2 == %{ "key1" => 1, "key2" => 1 })

    # the third result should have set the new value
    assert(result3 == %{ "key1" => 1, "key2" => "1", "key3" => 1 })
  end

  # This test just ensures that we correctly convert return values to either a
  # :commit Tuple or an :ignore Tuple. We also make sure to verify that the default
  # behaviour is a :commit Tuple for backwards compatibility.
  test "normalizing commit/ignore return values" do
    # define our base Tuples to test against
    tuple1 = { :commit, true }
    tuple2 = { :ignore, true }

    # define our base value
    value1 = true

    # normalize all values
    result1 = Cachex.Util.normalize_commit(tuple1)
    result2 = Cachex.Util.normalize_commit(tuple2)
    result3 = Cachex.Util.normalize_commit(value1)

    # the first two should persist
    assert(result1 == tuple1)
    assert(result2 == tuple2)

    # the value should be converted to the first
    assert(result3 == tuple1)
  end

  # We use milliseconds for dates around Cachex, so we just need to make sure we
  # have a utility function which does this safely for us. We create the miils
  # from an Erlang timestamp, just to make sure we have another tier of validation.
  test "retrieving the current time in milliseconds" do
    # pull the current timestamp
    { mega, seconds, ms } = :os.timestamp()

    # convert the timestamp to milliseconds
    millis = (mega * 1000000 + seconds) * 1000 + div(ms, 1000)

    # pull back the time from the util function
    current = Cachex.Util.now()

    # check they're the same (with an error bound of 2ms)
    assert_in_delta(current, millis, 2)
  end

  # This test just provides basic coverage of the write_mod function, by using
  # tags to determine the correct Action to use to write a value. We make sure
  # that the :missing and :new tags define a Set and the others define an Update.
  test "retrieving a module name to write with" do
    # ask for some modules
    result1 = Cachex.Util.write_mod(:new)
    result2 = Cachex.Util.write_mod(:missing)
    result3 = Cachex.Util.write_mod(:unknown)

    # the first two should be Set actions
    assert(result1 == Cachex.Actions.Set)
    assert(result2 == Cachex.Actions.Set)

    # the third should be an Update
    assert(result3 == Cachex.Actions.Update)
  end

  # There are several places we wish to fetch all rows from a cache, so this util
  # just generates a spec which takes a return set. All we can do here is check
  # that a specification is correctly generated with and without field indexes.
  test "selecting all rows in a match spec" do
    # generates two return types
    return1 = { :"$1", :"$2", :"$3", :"$4" }
    return2 = { :key, :touched, :ttl, :value }

    # create both specifications
    result1 = Cachex.Util.retrieve_all_rows(return1)
    result2 = Cachex.Util.retrieve_all_rows(return2)

    # both validate the same way
    validate = fn(result) ->
      # let's break down the result
      [ { head, query, return } ] = result

      # assert all makes sense
      assert(head == { :_, :"$1", :"$2", :"$3", :"$4" })
      assert(return == [ { :"$1", :"$2", :"$3", :"$4" } ])

      # the query has some dynamic values
      [ { :orelse, left, right } ] = query

      # validate the query
      assert(left == { :==, :"$3", nil })
      assert(match?({ :>, { :+, :"$2", :"$3" }, _now }, right))
    end

    # validate both results (as they should be the same)
    validate.(result1)
    validate.(result2)
  end

  # The reasoning for this test is the same as the above, but we need to ensure
  # that we only pull back expired rows rather than all of those inside the cache.
  test "selecting unexpired rows in a match spec" do
    # generates two return types
    return1 = { :"$1", :"$2", :"$3", :"$4" }
    return2 = { :key, :touched, :ttl, :value }

    # create both specifications
    result1 = Cachex.Util.retrieve_expired_rows(return1)
    result2 = Cachex.Util.retrieve_expired_rows(return2)

    # both validate the same way
    validate = fn(result) ->
      # let's break down the result
      [ { head, query, return } ] = result

      # assert all makes sense
      assert(head == { :_, :"$1", :"$2", :"$3", :"$4" })
      assert(return == [ { :"$1", :"$2", :"$3", :"$4" } ])

      # the query has some dynamic values
      [ { :andalso, left, right } ] = query

      # validate the query
      assert(left == { :"/=", :"$3", nil })
      assert(match?({ :<, { :+, :"$2", :"$3" }, _now }, right))
    end

    # validate both results (as they should be the same)
    validate.(result1)
    validate.(result2)
  end

  # This test simply validates the ability to retrieve and transform an option
  # from inside a Keyword List. We validate both existing and missing options in
  # order to make sure there are no issues when retrieving. We also verify the
  # result of the call is the transformed result.
  test "transforming an option value in a Keyword List" do
    # define our list of options
    options = [ key: "value" ]

    # define a transformer
    transformer = &({ &1 })

    # transformer various options
    result1 = Cachex.Util.opt_transform(options, :key, transformer)
    result2 = Cachex.Util.opt_transform(options, :nah, transformer)

    # only the first should come back
    assert(result1 == { "value" })
    assert(result2 == {   nil  })
  end
end
