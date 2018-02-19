defmodule Cachex.QueryTest do
  use CachexCase

  # All queries are run through the basic query generation, so this test
  # will just validate the passing of query clauses through to the query
  # creation default, which will attach the checks for expirations.
  test "creating basic queries" do
    # create a query with a true filter
    query1 = Cachex.Query.create(true)
    query2 = Cachex.Query.create(true, :key)

    # verify the form of the first query
    assert [
      {
        { :_, :"$1", :"$2", :"$3", :"$4" },
        [
          { :andalso,
            { :orelse,
              { :==, :"$3", nil },
              { :>, {:+, :"$2", :"$3" }, _now }
            },
            true
          }
        ],
        [ :"$_" ]
      }
    ] = query1

    # verify the form of the second query
    assert [
      {
        { :_, :"$1", :"$2", :"$3", :"$4" },
        [
          { :andalso,
            { :orelse,
              { :==, :"$3", nil },
              { :>, {:+, :"$2", :"$3" }, _now }
            },
            true
          }
        ],
        [ :"$1" ]
      }
    ] = query2
  end

  # The `expired()` function is just a wrapper to `create` whilst inverting
  # the expiration checks. This test just covers this behaviour.
  test "creating expired queries" do
    # create a couple of expired queries
    query1 = Cachex.Query.expired()
    query2 = Cachex.Query.expired(:key)

    # verify the form of the first query
    assert [
      {
        { :_, :"$1", :"$2", :"$3", :"$4" },
        [
          { :not,
            { :orelse,
              { :==, :"$3", nil },
              { :>, {:+, :"$2", :"$3" }, _now }
            }
          }
        ],
        [ :"$_" ]
      }
    ] = query1

    # verify the form of the second query
    assert [
      {
        { :_, :"$1", :"$2", :"$3", :"$4" },
        [
          { :not,
            { :orelse,
              { :==, :"$3", nil },
              { :>, {:+, :"$2", :"$3" }, _now }
            }
          }
        ],
        [ :"$1" ]
      }
    ] = query2
  end

  # The `unexpired()` function is just a wrapper to `create` whilst without a
  # secondary clause. This test just covers this behaviour.
  test "creating unexpired queries" do
    # create a couple of unexpired queries
    query1 = Cachex.Query.unexpired()
    query2 = Cachex.Query.unexpired(:key)

    # verify the form of the first query
    assert [
      {
        { :_, :"$1", :"$2", :"$3", :"$4" },
        [
          { :orelse,
            { :==, :"$3", nil },
            { :>, {:+, :"$2", :"$3" }, _now }
          }
        ],
        [ :"$_" ]
      }
    ] = query1

    # verify the form of the second query
    assert [
      {
        { :_, :"$1", :"$2", :"$3", :"$4" },
        [
          { :orelse,
            { :==, :"$3", nil },
            { :>, {:+, :"$2", :"$3" }, _now }
          }
        ],
        [ :"$1" ]
      }
    ] = query2
  end

  # This test just covers the default value checking when creating raw
  # queries with none of the provided bindings. This does nothing more
  # than validate structure, as there are no attached conditions added.
  test "creating raw queries" do
    # create a query with a true filter
    query1 = Cachex.Query.raw(true)
    query2 = Cachex.Query.raw(true, :key)

    # verify the form of the first query
    assert query1 == [
      {
        { :_, :"$1", :"$2", :"$3", :"$4" },
        [ true ],
        [ :"$_" ]
      }
    ]

    # verify the form of the second query
    assert query2 == [
      {
        { :_, :"$1", :"$2", :"$3", :"$4" },
        [ true ],
        [ :"$1" ]
      }
    ]
  end
end
