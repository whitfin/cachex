defmodule Cachex.StateTest do
  use PowerAssert, async: false

  alias Cachex.Options
  alias Cachex.State

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
    assert(State.set(__MODULE__, %State{ }))
  end

  test "update a state in the cache" do
    cworker = init_worker()
    nworker = init_worker([ remote: true ])

    assert(State.set(__MODULE__, cworker))

    new_state = State.update(__MODULE__, fn(%State{ }) ->
      nworker
    end)

    assert(new_state == nworker)
    assert(State.get(__MODULE__) == nworker)
  end

  defp init_worker(opts \\ []) do
    Options.parse([ { :name, __MODULE__ } | opts ])
  end

end
