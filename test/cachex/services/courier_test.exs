defmodule Cachex.Services.CourierTest do
  use CachexCase

  test "dispatching tasks" do
    # start a new cache
    cache = Helper.create_cache()
    cache = Services.Overseer.retrieve(cache)

    # dispatch an arbitrary task
    result = Services.Courier.dispatch(cache, "my_key", fn ->
      "my_value"
    end)

    # check the returned value
    assert result == { :commit, "my_value" }

    # check the key was placed in the table
    retrieved = Cachex.get(cache, "my_key")

    # the retrieved value should match
    assert retrieved == { :ok, "my_value" }
  end

  test "dispatching tasks from multiple processes" do
    # create a hook for forwarding
    { :ok, agent } = Agent.start_link(fn -> :ok end)

    # define our task function
    task = fn ->
      :timer.sleep(250) && "my_value"
    end

    # start a new cache
    cache = Helper.create_cache()
    cache = Services.Overseer.retrieve(cache)
    parent = self()

    # dispatch an arbitrary task from the agent process
    Agent.cast(agent, fn _ ->
      send(parent, Services.Courier.dispatch(cache, "my_key", task))
    end)

    # dispatch an arbitrary task from the current process
    result = Services.Courier.dispatch(cache, "my_key", task)

    # check the forwarded task completed
    assert_receive({ :commit, "my_value" })

    # check the returned value
    assert result == { :commit, "my_value" }

    # check the key was placed in the table
    retrieved = Cachex.get(cache, "my_key")

    # the retrieved value should match
    assert retrieved == { :ok, "my_value" }
  end

  test "gracefully handling crashes inside tasks" do
    # start a new cache
    cache = Helper.create_cache()
    cache = Services.Overseer.retrieve(cache)

    # dispatch an arbitrary task
    result = Services.Courier.dispatch(cache, "my_key", fn ->
      raise ArgumentError
    end)

    # check the returned value
    assert result == { :error, "argument error" }
  end
end
