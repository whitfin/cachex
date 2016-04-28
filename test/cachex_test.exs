defmodule CachexTest do
  use PowerAssert

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
    this_proc = self()

    proc_pid = spawn(fn ->
      Cachex.start_link([name: state.name, default_ttl: :timer.seconds(3)])
      :erlang.send_after(1, this_proc, { self, :started })
    end)

    receive do
      { ^proc_pid, :started } ->
        get_result = Cachex.get(state.name, "key")
        assert(get_result == { :error, "Invalid cache provided, got: #{inspect(state.name)}" })
    after
      50 -> flunk("Expected cache to be started!")
    end
  end

  test "starting a cache using spawn with start/1 does not die immediately", state do
    this_proc = self()

    proc_pid = spawn(fn ->
      Cachex.start([name: state.name, default_ttl: :timer.seconds(3)])
      :erlang.send_after(1, this_proc, { self, :started })
    end)

    receive do
      { ^proc_pid, :started } ->
        get_result = Cachex.get(state.name, "key")
        assert(get_result == { :missing, nil })
    after
      50 -> flunk("Expected cache to be started!")
    end
  end

end
