defmodule Cachex.StateTest do
  use PowerAssert

  alias Cachex.Options
  alias Cachex.State
  alias Cachex.Worker

  setup do
    State.start()
    State.del(__MODULE__)
    :ok
  end

  test "retrieving a state from the cache" do
    worker = init_worker()

    assert(State.set(__MODULE__, worker))
    assert(State.get(__MODULE__) == worker)
  end

  test "setting a state in the cache" do
    worker = Worker.init(%Options{ })

    assert(State.set(__MODULE__, worker))
  end

  test "update a state in the cache" do
    cworker = init_worker()
    nworker = init_worker([ remote: true ])

    assert(State.set(__MODULE__, cworker))

    new_state = State.update(__MODULE__, fn(%Worker{ }) ->
      nworker
    end)

    assert(new_state == nworker)
    assert(State.get(__MODULE__) == nworker)
  end

  test "starting from a spawn will live using start" do
    Agent.stop(:cachex_state_tm)

    assert(Process.whereis(:cachex_state_tm) == nil)

    spawn(fn ->
      State.start()
    end)

    :timer.sleep(1)

    assert(Process.whereis(:cachex_state_tm) != nil)
  end

  defp init_worker(opts \\ []) do
    [ { :name, __MODULE__ } | opts ] |> Options.parse |> Worker.init
  end

end
