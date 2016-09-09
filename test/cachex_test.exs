defmodule CachexTest do
  use PowerAssert, async: false

  setup do
    Application.ensure_all_started(:cachex)

    name =
      16
      |> TestHelper.gen_random_string_of_length
      |> String.to_atom

    { :ok, cache: TestHelper.create_cache(), name: name }
  end

  test "cache start without application start", state do
    ExUnit.CaptureLog.capture_log(fn ->
      Application.stop(:cachex)
    end)

    assert(Cachex.start(state.name) == {:error, "Cachex tables not initialized, did you start the Cachex application?"})
  end

  test "cache start_link with name as first argument", state do
    on_exit("delete #{state.name}", fn ->
      :ets.delete(state.name)
    end)

    { status, pid } = Cachex.start_link(state.name)
    assert(status == :ok)
    assert(is_pid(pid))
  end

  test "cache start_link with name in options", state do
    on_exit("delete #{state.name}", fn ->
      :ets.delete(state.name)
    end)

    { status, pid } = Cachex.start_link([ name: state.name ])
    assert(status == :ok)
    assert(is_pid(pid))
  end

  test "cache start with name as first argument", state do
    on_exit("delete #{state.name}", fn ->
      :ets.delete(state.name)
    end)

    { status, pid } = Cachex.start(state.name)
    assert(status == :ok)
    assert(is_pid(pid))
  end

  test "cache start with name in options", state do
    on_exit("delete #{state.name}", fn ->
      :ets.delete(state.name)
    end)

    { status, pid } = Cachex.start([ name: state.name ])
    assert(status == :ok)
    assert(is_pid(pid))
  end

  test "cache start with invalid name", _state do
    start_result = Cachex.start_link([ name: "test" ])
    assert(start_result == { :error, "Cache name must be a valid atom" })
  end

  test "cache started twice returns an error", state do
    { status, pid } = Cachex.start_link(state.name)
    assert(status == :ok)
    assert(is_pid(pid))

    start_result = Cachex.start_link(state.name)
    assert(start_result == { :error, "Cache name already in use!" })
  end

  test "cache started with invalid ets options", state do
    start_result = Cachex.start_link(state.name, [ ets_opts: [{ :yolo, true }] ])
    assert(start_result == { :error, :invalid_opts })
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

  test "command execution requires both a supervisor and a state", state do
    Cachex.State.del(state.name)

    get_result = Cachex.get(state.name, "key")

    assert(get_result == { :error, "Invalid cache provided, got: #{inspect(state.name)}" })
  end

end
