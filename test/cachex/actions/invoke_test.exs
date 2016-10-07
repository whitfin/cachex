defmodule Cachex.Actions.InvokeTest do
  use CachexCase

  test "invoking custom commands" do
    # create a list left pop
    lpop = fn([ head | tail ]) ->
      { head, tail }
    end

    # create a list right pop
    rpop = fn(list) ->
      { List.last(list), :lists.droplast(list) }
    end

    # create a test cache
    cache = Helper.create_cache([
      commands: [
        last: { :return, &List.last/1 },
        lpop: { :modify, lpop },
        rpop: { :modify, rpop }
      ]
    ])

    # set a list inside the cache
    { :ok, true } = Cachex.set(cache, "list", [ 1, 2, 3, 4, 5 ])

    # retrieve the raw record
    { "list", touched, nil, _val } = Cachex.inspect!(cache, { :record, "list" })

    # execute some custom commands
    last1 = Cachex.invoke(cache, :last, "list")
    lpop1 = Cachex.invoke(cache, :lpop, "list")
    lpop2 = Cachex.invoke(cache, :lpop, "list")
    rpop1 = Cachex.invoke(cache, :rpop, "list")
    rpop2 = Cachex.invoke(cache, :rpop, "list")
    last2 = Cachex.invoke(cache, :last, "list")

    # verify that all results are as expected
    assert(last1 == { :ok, 5 })
    assert(lpop1 == { :ok, 1 })
    assert(lpop2 == { :ok, 2 })
    assert(rpop1 == { :ok, 5 })
    assert(rpop2 == { :ok, 4 })
    assert(last2 == { :ok, 3 })

    # retrieve the raw record again
    inspect1 = Cachex.inspect(cache, { :record, "list" })

    # verify the touched time was unchanged
    assert(inspect1 == { :ok, { "list", touched, nil, [ 3 ] }})

    # try to invoke a missing command
    invoke1 = Cachex.invoke(cache, :invoke, "heh")

    # it should be an error
    assert(invoke1 == { :error, :invalid_command })
  end

end
