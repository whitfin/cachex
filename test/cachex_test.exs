defmodule CachexTest do
  use PowerAssert

  setup do
    { :ok, cache: TestHelper.create_cache(), name: String.to_atom(TestHelper.gen_random_string_of_length(16)) }
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
    start_result = Cachex.start_link([name: state.name, nodes: ["failnode@testhost.com"]])
    assert(start_result == { :error, "Mnesia table setup failed due to {:aborted, {:bad_type, :#{state.name}, \"failnode@testhost.com\"}}" })
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

end
