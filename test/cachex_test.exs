defmodule CachexTest do
  use PowerAssert

  @testhost Cachex.Util.create_node_name("cachex_test")

  setup do
    name =
      16
      |> TestHelper.gen_random_string_of_length
      |> String.to_atom

    { :ok, cache: TestHelper.create_cache(), name: name }
  end

  test "starting a cache with an invalid name", _state do
    start_result = Cachex.start_link([name: "test"])
    assert(start_result == { :error, "Cache name must be a valid atom" })
  end

  test "starting a cache twice returns an error", state do
    { status, pid } = Cachex.start_link([name: state.name])
    assert(status == :ok)
    assert(is_pid(pid))

    fake_pid =
      pid
      |> Kernel.inspect
      |> String.slice(5..10)
      |> String.split(".")
      |> Enum.at(1)
      |> Integer.parse
      |> Kernel.elem(0)
      |> (&(:c.pid(0, &1 + 1, 0))).()

    start_result = Cachex.start_link([name: state.name])
    assert(start_result == { :error, "Cache name already in use for #{inspect(fake_pid)}" })
  end

  test "starting a cache over an invalid mnesia table", state do
    start_result = Cachex.start_link([name: state.name, ets_opts: [{ :yolo, true }]])
    assert(start_result == { :error, "Mnesia table setup failed due to {:aborted, {:system_limit, :#{state.name}, {'Failed to create ets table', :badarg}}}" })
  end

  test "defwrap macro cannot accept non-atom or non-worker caches", _state do
    get_result = Cachex.get("test", "key")
    assert(get_result == { :error, "Invalid cache provided, got: \"test\"" })
  end

  test "defwrap macro provides unsafe wrappers", state do
    set_result = Cachex.set!(state.cache, "key", "value")
    assert(set_result == true)

    get_result = Cachex.get!(state.cache, "key")
    assert(get_result == "value")

    assert_raise(Cachex.ExecutionError, "Invalid cache provided, got: \"test\"", fn ->
      Cachex.get!("test", "key")
    end)
  end

  test "starting a cache using spawn with start_link/2 dies immediately", state do
    spawn(fn -> Cachex.start_link([name: state.name, default_ttl: :timer.seconds(3)]) end)
    :timer.sleep(2)
    get_result = Cachex.get(state.name, "key")
    assert(get_result == { :error, "Invalid cache provided, got: #{inspect(state.name)}" })
  end

  test "starting a cache using spawn with start/1 does not die immediately", state do
    spawn(fn -> Cachex.start([name: state.name, default_ttl: :timer.seconds(3)]) end)
    :timer.sleep(2)
    get_result = Cachex.get(state.name, "key")
    assert(get_result == { :missing, nil })
  end

  test "joining an existing remote cluster", state do
    cache_args = [name: state.name, nodes: [ node(), @testhost ] ]

    { rpc_status, rpc_result } = TestHelper.start_remote_cache(@testhost, [cache_args])

    assert(rpc_status == :ok)
    assert(is_pid(rpc_result))

    set_result = TestHelper.remote_call(@testhost, :set, [state.name, "remote_key_test", "remote_value"])

    assert(set_result == { :ok, true })

    cache = TestHelper.create_cache(cache_args ++ [name: state.name])

    get_result = Cachex.get(cache, "remote_key_test")

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

  test "adding a node to a transactional cache", _state do
    cache = TestHelper.create_cache([ transactional: true ])

    worker = Cachex.inspect!(cache, :state)

    assert(worker.actions == Cachex.Worker.Transactional)
    assert(worker.options.nodes == [node])

    add_result = Cachex.add_node(cache, @testhost)

    assert(add_result == { :ok, true })

    worker = Cachex.inspect!(cache, :state)

    assert(worker.actions == Cachex.Worker.Transactional)
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
