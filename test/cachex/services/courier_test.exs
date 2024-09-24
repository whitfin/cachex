defmodule Cachex.Services.CourierTest do
  use Cachex.Test.Case

  test "dispatching tasks" do
    # start a new cache
    cache = TestUtils.create_cache()
    cache = Services.Overseer.retrieve(cache)

    # dispatch an arbitrary task
    result =
      Services.Courier.dispatch(cache, "my_key", fn ->
        "my_value"
      end)

    # check the returned value
    assert result == {:commit, "my_value"}

    # check the key was placed in the table
    retrieved = Cachex.get(cache, "my_key")

    # the retrieved value should match
    assert retrieved == {:ok, "my_value"}
  end

  test "dispatching tasks from multiple processes" do
    # create a hook for forwarding
    {:ok, agent} = Agent.start_link(fn -> :ok end)

    # define our task function
    task = fn ->
      :timer.sleep(500)
      {:commit, "my_value", expire: :timer.seconds(60)}
    end

    # start a new cache
    cache = TestUtils.create_cache()
    cache = Services.Overseer.retrieve(cache)
    parent = self()

    # dispatch an arbitrary task from the agent process
    Agent.cast(agent, fn _ ->
      send(parent, Services.Courier.dispatch(cache, "my_key", task))
    end)

    # dispatch an arbitrary task from the current process
    result = Services.Courier.dispatch(cache, "my_key", task)

    # check the returned value with the options set
    assert result == {:commit, "my_value", [expire: 60000]}

    # check the forwarded task completed (no options)
    assert_receive({:ok, "my_value"})

    # check the key was placed in the table
    retrieved = Cachex.get(cache, "my_key")

    # the retrieved value should match
    assert retrieved == {:ok, "my_value"}
  end

  test "gracefully handling crashes inside tasks" do
    # start a new cache
    cache = TestUtils.create_cache()
    cache = Services.Overseer.retrieve(cache)

    # dispatch an arbitrary task
    result =
      Services.Courier.dispatch(cache, "my_key", fn ->
        raise ArgumentError
      end)

    # check the returned value contains the error and the stack trace
    assert match?({:error, %Cachex.Error{}}, result)
    assert elem(result, 1).message == "argument error"
  end

  test "recovering from failed tasks" do
    # start a new cache
    cache = TestUtils.create_cache()
    cache = Services.Overseer.retrieve(cache)

    # kill in flight task
    parent =
      spawn(fn ->
        receive do
          pid -> Process.exit(pid, :kill)
        end
      end)

    # dispatch a long running task
    result =
      Services.Courier.dispatch(cache, "my_key", fn ->
        send(parent, self())
        :timer.sleep(60000)
      end)

    # check we caught the killed task
    assert result == {:error, :killed}
  end
end
