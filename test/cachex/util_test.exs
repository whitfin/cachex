defmodule Cachex.UtilTest do
  use CachexCase

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

  # This test just ensures that we correctly convert return values to either a
  # :commit Tuple or an :ignore Tuple. We also make sure to verify that the default
  # behaviour is a :commit Tuple for backwards compatibility.
  test "normalizing commit/ignore return values" do
    # define our base Tuples to test against
    tuple1 = { :commit, true }
    tuple2 = { :ignore, true }
    tuple3 = { :error,  true }

    # define our base value
    value1 = true

    # normalize all values
    result1 = Cachex.Util.normalize_commit(tuple1)
    result2 = Cachex.Util.normalize_commit(tuple2)
    result3 = Cachex.Util.normalize_commit(tuple3)
    result4 = Cachex.Util.normalize_commit(value1)

    # the first three should persist
    assert(result1 == tuple1)
    assert(result2 == tuple2)
    assert(result3 == tuple3)

    # the value should be converted to the first
    assert(result4 == tuple1)
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
end
