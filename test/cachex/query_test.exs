defmodule Cachex.QueryTest do
  use CachexCase

  # All queries are run through the basic query generation, so this test
  # will just validate the passing of query clauses through to the query
  # creation default, which will attach the checks for expirations.
  test "creating basic queries" do
    # create a query with a true filter
    query1 = Cachex.Query.where(true)
    query2 = Cachex.Query.where(true, :key)

    # verify the mapping of both queries
    assert [{{:_, :"$1", :"$2", :"$3", :"$4"}, _, _}] = query1
    assert [{{:_, :"$1", :"$2", :"$3", :"$4"}, _, _}] = query2

    # unpack clauses of both queries
    [{_, [{:andalso, c1, true}], _}] = query1
    [{_, [{:andalso, c2, true}], _}] = query2

    # verify the queries of both queries
    assert {:orelse, {:==, :"$3", nil}, {:>, {:+, :"$2", :"$3"}, _now}} = c1
    assert {:orelse, {:==, :"$3", nil}, {:>, {:+, :"$2", :"$3"}, _now}} = c2

    # verify the returns of both queries
    assert [{_, _, [:"$_"]}] = query1
    assert [{_, _, [:"$1"]}] = query2
  end

  # The `expired()` function is just a wrapper to `where` whilst inverting
  # the expiration checks. This test just covers this behaviour.
  test "creating expired queries" do
    # create a couple of expired queries
    query1 = Cachex.Query.expired()
    query2 = Cachex.Query.expired(:key)

    # verify the mapping of both queries
    assert [{{:_, :"$1", :"$2", :"$3", :"$4"}, _, _}] = query1
    assert [{{:_, :"$1", :"$2", :"$3", :"$4"}, _, _}] = query2

    # unpack clauses of both queries
    [{_, [{:not, c1}], _}] = query1
    [{_, [{:not, c2}], _}] = query2

    # verify the queries of both queries
    assert {:orelse, {:==, :"$3", nil}, {:>, {:+, :"$2", :"$3"}, _now}} = c1
    assert {:orelse, {:==, :"$3", nil}, {:>, {:+, :"$2", :"$3"}, _now}} = c2

    # verify the returns of both queries
    assert [{_, _, [:"$_"]}] = query1
    assert [{_, _, [:"$1"]}] = query2
  end

  # The `unexpired()` function is just a wrapper to `create` whilst without a
  # secondary clause. This test just covers this behaviour.
  test "creating unexpired queries" do
    # create a couple of unexpired queries
    query1 = Cachex.Query.unexpired()
    query2 = Cachex.Query.unexpired(:key)

    # verify the mapping of both queries
    assert [{{:_, :"$1", :"$2", :"$3", :"$4"}, _, _}] = query1
    assert [{{:_, :"$1", :"$2", :"$3", :"$4"}, _, _}] = query2

    # unpack clauses of both queries
    [{_, [c1], _}] = query1
    [{_, [c2], _}] = query2

    # verify the queries of both queries
    assert {:orelse, {:==, :"$3", nil}, {:>, {:+, :"$2", :"$3"}, _now}} = c1
    assert {:orelse, {:==, :"$3", nil}, {:>, {:+, :"$2", :"$3"}, _now}} = c2

    # verify the returns of both queries
    assert [{_, _, [:"$_"]}] = query1
    assert [{_, _, [:"$1"]}] = query2
  end

  # This test just covers the default value checking when creating raw
  # queries with none of the provided bindings. This does nothing more
  # than validate structure, as there are no attached conditions added.
  test "creating raw queries" do
    # create a query with a true filter
    query1 = Cachex.Query.raw(true)
    query2 = Cachex.Query.raw(true, :key)

    # verify the form of the first query
    assert [{{:_, :"$1", :"$2", :"$3", :"$4"}, _, _}] = query1
    assert [{_, [true], _}] = query1
    assert [{_, _, [:"$_"]}] = query1

    # verify the form of the second query
    assert [{{:_, :"$1", :"$2", :"$3", :"$4"}, _, _}] = query2
    assert [{_, [true], _}] = query2
    assert [{_, _, [:"$1"]}] = query2
  end
end
