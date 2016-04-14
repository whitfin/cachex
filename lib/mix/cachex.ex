defmodule Mix.Cachex do
  @moduledoc false
  # A utility lib for binding all required slave nodes. Provides options to start
  # and stop any required slave nodes, denoted by `@nodenames`. Also provides a
  # `run_task/1` interface which will run the provided function in the scope of
  # bound nodes.

  # import utils
  import Cachex.Util

  # our list of nodes to create, based on tests
  @nodenames [
    create_node_name("cachex_test")
  ]

  @doc """
  A small handler to bind any slave nodes to this Mix setup. We first name this
  node as Mix doesn't set itself up with a node name. Then we iterate through all
  node names and start a `ct_slave`. From that point we ensure that Mnesia is
  started on each slave node, and that the Cachex module is available to the node.
  """
  def start do
    :net_kernel.start([ :cachex_base_node, :shortnames ])

    Enum.each(@nodenames, fn(node) ->
      stop_node(node)

      :ct_slave.start(node)
      :net_adm.ping(node)

      :rpc.call(node, :mnesia, :start, [])
      :rpc.call(node, :code, :add_paths, [:code.get_path])
    end)
  end

  @doc """
  Small handler to stop the slave nodes, simply iterating the names of the nodes
  and terminating them.
  """
  def stop do
    Enum.each(@nodenames, &stop_node/1)
  end

  @doc """
  Convenience handler for executing a given function without having to start/stop
  any required nodes. Simply starts all nodes, executes the function, and then
  closes all nodes.
  """
  def run_task(task) when is_function(task) do
    start()
    task.()
    stop()
  end

  # Stops a local node - shorthand binding because we stop nodes both before and
  # after tasks are run. We have to do some fun stuff to split up the host because
  # otherwise we end up with @host@host as a suffix.
  defp stop_node(node) do
    [ name, host ] =
      node
      |> Kernel.to_string
      |> String.split("@", parts: 2)
      |> Enum.map(&String.to_atom/1)

    :ct_slave.stop(host, name)
  end

end
