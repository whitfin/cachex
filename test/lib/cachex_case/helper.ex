defmodule CachexCase.Helper do
  @moduledoc false
  # This module contains various helper functions for tests.
  #
  # Utilities such as shorthanding the ability to create caches, polling
  # for messages, and polling for conditions. Generally it just makes writing
  # tests a lot easier and more convenient.
  import Cachex.Spec
  import ExUnit.Assertions

  # a list of letters A - Z
  @alphabet Enum.to_list(?a..?z)

  @doc false
  # Creates a cache using the given arguments to construct the cache options.
  #
  # We return the name in case we're using the defaults, so that callers can
  # generate a random cache with a random name. We make sure to trigger a
  # delete to happen on test exit in order to avoid bloating ETS and memory
  # unnecessarily.
  def create_cache(args \\ []) do
    name = create_name()
    {:ok, _pid} = Cachex.start_link(name, args)
    delete_on_exit(name)
  end

  @doc false
  # Creates a cache cluster using the given arguments to construct the cache.
  #
  # The name of the cache is returned, along with the names of the nodes in
  # the cluster to enable calling out directly.
  def create_cache_cluster(amount, args \\ []) when is_integer(amount) do
    # no-op when done multiple times
    LocalCluster.start()

    name = create_name()
    nodes = [node() | LocalCluster.start_nodes(name, amount - 1)]

    # basic match to ensure that the result is as expected
    {[{:ok, _pid1}, {:ok, _pid2}], []} =
      :rpc.multicall(
        nodes,
        Cachex,
        :start,
        [name, [nodes: nodes] ++ args]
      )

    # stop all children on exit, even though it's automatic
    TestHelper.on_exit("stop #{name} children", fn ->
      Supervisor.stop(name)

      nodes
      |> List.delete(node())
      |> LocalCluster.stop_nodes()
    end)

    {name, nodes}
  end

  @doc false
  # Creates a warmer module.
  #
  # This will name the module after the provided name, and create it with
  # the provided interval definition and execution. This is a shorthand to
  # avoid having to define modules all over the codebase, but does not change
  # the outcomes in any way (still a new module being defined).
  defmacro create_warmer(name, interval, execution) do
    quote do
      defmodule unquote(name) do
        use Cachex.Warmer

        def interval,
          do: unquote(interval)

        def execute(state),
          do: apply(unquote(execution), [state])
      end
    end
  end

  @doc false
  # Creates a cache name.
  #
  # These names are atoms of 8 random characters between the letters A - Z. This
  # is used to generate random cache names for tests.
  def create_name do
    8
    |> gen_rand_bytes
    |> String.to_atom()
  end

  @doc false
  # Triggers a cache to be deleted at the end of the test.
  #
  # We have to pass this through to the `TestHelper` module as we don't have a
  # valid ExUnit context to be able to define the execution hook correctly.
  def delete_on_exit(name),
    do: TestHelper.delete_on_exit(name) && name

  @doc false
  # Flush all messages in the process queue.
  def flush do
    receive do
      _ -> flush()
    after
      0 -> nil
    end
  end

  @doc false
  # Generates a number of random bytes.
  #
  # Bytes will be returned as a binary, and can be used to generate alphabetic
  # names and (sufficiently) random keys throughout test cycles.
  def gen_rand_bytes(num) when is_number(num) do
    1..num
    |> Enum.map(fn _ -> Enum.random(@alphabet) end)
    |> List.to_string()
  end

  @doc false
  # Provides the ability to poll for a condition to become true.
  #
  # Truthiness is  calculated using assertions. If the condition fails, we try
  # again over and over until a threshold is hit. Once the threshold is hit, we
  # raise the last known assertion error to bubble back to ExUnit.
  def poll(timeout, expected, generator, start_time \\ now()) do
    try do
      assert(generator.() == expected)
    rescue
      e ->
        unless start_time + timeout > now() do
          raise e
        end

        poll(timeout, expected, generator, start_time)
    end
  end
end
