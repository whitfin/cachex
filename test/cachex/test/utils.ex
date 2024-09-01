defmodule Cachex.Test.Utils do
  @moduledoc false
  # This module contains various helper functions for tests.
  #
  # Utilities such as shorthanding the ability to create caches, polling
  # for messages, and polling for conditions. Generally it just makes writing
  # tests a lot easier and more convenient.
  import Cachex.Spec
  import ExUnit.Assertions

  # alias the hooks to their legacy names
  alias Cachex.Test.Hook.Execute, as: ExecuteHook
  alias Cachex.Test.Hook.Forward, as: ForwardHook

  # require hook related macros
  require ExecuteHook
  require ForwardHook

  # create default execute hook
  ExecuteHook.bind(default_execute_hook: [])

  # create default forward hook
  ForwardHook.bind(default_forward_hook: [])

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

    # create our cluster and fetch back our node list
    {:ok, cluster} = LocalCluster.start_link(amount - 1)
    {:ok, nodes} = LocalCluster.nodes(cluster)

    # create a cache name
    name = create_name()
    nodes = [node() | nodes]

    # basic match to ensure that the result is as expected
    {results, []} =
      :rpc.multicall(
        nodes,
        Cachex,
        :start,
        [name, args ++ [router: router(module: Cachex.Router.Jump)]]
      )

    # double check all pids
    for result <- results do
      assert match?({:ok, pid} when is_pid(pid), result)
    end

    # cleanup the cache
    delete_on_exit(name)

    # wait for all nodes to disconnect before continue
    on_exit("stop #{name} children", fn ->
      poll(250, [], fn -> Node.list(:connected) end)
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
  # These names start and end with _ with 8 A-Z letters in between. This is used
  # to generate random cache names for tests. The underscores are to ensure we
  # keep a guaranteed sorting order when using distributed clusters.
  def create_name,
    do: String.to_atom("_#{gen_rand_bytes(8)}_")

  @doc false
  # Triggers a cache to be deleted at the end of the test.
  def delete_on_exit(name) do
    on_exit("delete #{name}", fn ->
      try do
        Supervisor.stop(name)
      catch
        :exit, _ -> :ok
      end
    end)

    name
  end

  @doc false
  # Runs a callable action by name on exit.
  defdelegate on_exit(name, action),
    to: ExUnit.Callbacks

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
      assert generator.() == expected
    rescue
      e ->
        unless start_time + timeout > now() do
          raise e
        end

        poll(timeout, expected, generator, start_time)
    end
  end
end
