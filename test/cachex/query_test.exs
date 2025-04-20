defmodule Cachex.QueryTest do
  use Cachex.Test.Case

  test "creating basic queries" do
    # create a query with not filter
    query1 = Cachex.Query.build()
    query2 = Cachex.Query.build(output: :key)

    # verify the mapping of both queries
    assert [{{:_, :"$1", :"$2", :"$3", :"$4"}, _, _}] = query1
    assert [{{:_, :"$1", :"$2", :"$3", :"$4"}, _, _}] = query2

    # unpack clauses of both queries
    [{_, [true], _}] = query1
    [{_, [true], _}] = query2

    # verify the returns of both queries
    assert [{_, _, [:"$_"]}] = query1
    assert [{_, _, [:"$1"]}] = query2
  end

  test "creating expired queries" do
    # create base expired filter
    filter1 = Cachex.Query.expired()
    filter2 = Cachex.Query.expired(false)

    # create a couple of expired queries
    clause1 = Cachex.Query.build(where: filter1)
    clause2 = Cachex.Query.build(where: filter1, output: :key)
    clause3 = Cachex.Query.build(where: filter2)

    # verify the mapping of both queries
    assert [{{:_, :"$1", :"$2", :"$3", :"$4"}, _, _}] = clause1
    assert [{{:_, :"$1", :"$2", :"$3", :"$4"}, _, _}] = clause2
    assert [{{:_, :"$1", :"$2", :"$3", :"$4"}, _, _}] = clause3

    # unpack clauses of both queries
    [{_, [{:not, c1}], _}] = clause1
    [{_, [{:not, c2}], _}] = clause2
    [{_, [{:andalso, {:not, c3}, false}], _}] = clause3

    # verify the queries of both queries
    assert {:orelse, {:==, :"$4", nil}, {:>, {:+, :"$3", :"$4"}, _now}} = c1
    assert {:orelse, {:==, :"$4", nil}, {:>, {:+, :"$3", :"$4"}, _now}} = c2
    assert {:orelse, {:==, :"$4", nil}, {:>, {:+, :"$3", :"$4"}, _now}} = c3

    # verify the returns of both queries
    assert [{_, _, [:"$_"]}] = clause1
    assert [{_, _, [:"$1"]}] = clause2
    assert [{_, _, [:"$_"]}] = clause3
  end

  test "creating unexpired queries" do
    # create base unexpired filter
    filter1 = Cachex.Query.unexpired()
    filter2 = Cachex.Query.unexpired(false)

    # create a couple of unexpired queries
    clause1 = Cachex.Query.build(where: filter1)
    clause2 = Cachex.Query.build(where: filter1, output: :key)
    clause3 = Cachex.Query.build(where: filter2)

    # verify the mapping of both queries
    assert [{{:_, :"$1", :"$2", :"$3", :"$4"}, _, _}] = clause1
    assert [{{:_, :"$1", :"$2", :"$3", :"$4"}, _, _}] = clause2
    assert [{{:_, :"$1", :"$2", :"$3", :"$4"}, _, _}] = clause3

    # unpack clauses of both queries
    [{_, [c1], _}] = clause1
    [{_, [c2], _}] = clause2
    [{_, [c3], _}] = clause3

    # verify the queries of all queries
    assert {:orelse, {:==, :"$4", nil}, {:>, {:+, :"$3", :"$4"}, _now}} = c1
    assert {:orelse, {:==, :"$4", nil}, {:>, {:+, :"$3", :"$4"}, _now}} = c2
    assert {:andalso, {:orelse, {:==, :"$4", nil}, {:>, {:+, :"$3", :"$4"}, _now}}, false} = c3

    # verify the returns of both queries
    assert [{_, _, [:"$_"]}] = clause1
    assert [{_, _, [:"$1"]}] = clause2
    assert [{_, _, [:"$_"]}] = clause3
  end
end
