defmodule Mix.Cachex do
  @moduledoc false
  # A utility lib for binding all required slave nodes. Provides options to start
  # and stop any required slave nodes, denoted by `@nodenames`. Also provides a
  # `run_task/1` interface which will run the provided function in the scope of
  # bound nodes.

  # import utilities
  import Cachex.Util

  # our list of nodes to create, based on tests
  @nodenames [
    create_node_name("cachex_test")
  ]

  @doc """
  Runs a task in a node context.

  Internally this just delegates to using `run_task/1` for convenience.
  """
  def run_in_context(task, args \\ []) when is_binary(task),
  do: run_task(fn -> Mix.Task.run(task, args) end)

  @doc """
  Runs a task with automatic starting/stopping of any required nodes.

  Simply starts all nodes, executes the function, and then closes all nodes.
  """
  def run_task(task) when is_function(task) do
    start()
    task.()
    stop()
  end

  @doc """
  Starts a number of slaves nodes against this Mix instance.

  We first name this node as Mix doesn't set itself up with a node name. Then we
  iterate through all node names and start a `ct_slave`. From that point we ensure
  that Mnesia is started on each slave node, and that the Cachex module is available
  to the node.
  """
  def start do
    :net_kernel.start([ :cachex_base_node, :shortnames ])

    Enum.each(@nodenames, fn(name) ->
      stop_node(name) && start_node(name)

      :net_adm.ping(name)

      :rpc.call(name, :mnesia, :start, [])
      :rpc.call(name, :code, :add_paths, [:code.get_path])
      :rpc.call(name, :application, :ensure_all_started, [:cachex])
    end)
  end

  @doc """
  Stops any slave nodes by iterating the names of the nodes and terminating them.
  """
  def stop, do: Enum.each(@nodenames, &stop_node/1)

  # Starts a local node using the :slave module.
  defp start_node(longname) do
    [ name, host ] =
      longname
      |> Kernel.to_string
      |> String.split("@", parts: 2)
      |> Enum.map(&String.to_atom/1)

    :slave.start_link(host, name)
  end

  # Stops a local node using the :slave module.
  defdelegate stop_node(name), to: :slave, as: :stop

end
