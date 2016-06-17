defmodule Cachex.ReplicationTest do
  use PowerAssert, async: false

  @testhost Cachex.Util.create_node_name("cachex_test")

  setup do
    name =
      16
      |> TestHelper.gen_random_string_of_length
      |> String.to_atom

    { :ok, cache: TestHelper.create_cache(), name: name }
  end

  test "joining an existing remote cluster", state do
    cache_args = [ name: state.name, nodes: [ node(), @testhost ] ]

    { rpc_status, rpc_result } =
      @testhost
      |> TestHelper.start_remote_cache([cache_args])

    assert(rpc_status == :ok)
    assert(is_pid(rpc_result))

    set_result =
      @testhost
      |> TestHelper.remote_call(:set, [state.name, "remote_key_test", "remote_value"])

    assert(set_result == { :ok, true })

    get_result =
      cache_args
      |> TestHelper.create_cache
      |> Cachex.get("remote_key_test")

    assert(get_result == { :ok, "remote_value" })
  end

  test "adding a node to an existing cache", state do
    worker = Cachex.inspect!(state.cache, :state)

    assert(worker.actions == Cachex.Worker.Local)
    assert(worker.options.nodes == [node])

    add_result = Cachex.add_node(state.cache, @testhost)

    assert(add_result == { :ok, true })

    worker = Cachex.inspect!(state.cache, :state)

    assert(worker.actions == Cachex.Worker.Remote)
    assert(worker.options.nodes == [@testhost, node])
  end

  test "adding a node twice to an existing cache", state do
    worker = Cachex.inspect!(state.cache, :state)

    assert(worker.actions == Cachex.Worker.Local)
    assert(worker.options.nodes == [node])

    add_result = Cachex.add_node(state.cache, @testhost)

    assert(add_result == { :ok, true })

    add_result = Cachex.add_node(state.cache, @testhost)

    assert(add_result == { :ok, true })

    worker = Cachex.inspect!(state.cache, :state)

    assert(worker.actions == Cachex.Worker.Remote)
    assert(worker.options.nodes == [@testhost, node])
  end

  test "adding a node to an existing cache with a worker", state do
    worker = Cachex.inspect!(state.cache, :state)

    assert(worker.actions == Cachex.Worker.Local)
    assert(worker.options.nodes == [node])

    add_result = Cachex.add_node(worker, @testhost)

    assert(add_result == { :ok, true })

    worker = Cachex.inspect!(state.cache, :state)

    assert(worker.actions == Cachex.Worker.Remote)
    assert(worker.options.nodes == [@testhost, node])
  end

  test "adding a node using a missing node name", state do
    add_result = Cachex.add_node(state.cache, :random_missing_node)

    assert(add_result == { :error, "Unable to reach remote node!" })
  end

  test "adding a node using non-atom", state do
    assert_raise(FunctionClauseError, fn ->
      Cachex.add_node(state.cache, "test")
    end)
  end

end
