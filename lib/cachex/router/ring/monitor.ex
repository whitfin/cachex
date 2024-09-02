defmodule Cachex.Router.Ring.Monitor do
  @moduledoc false
  # Small monitor implementation for ring nodes.
  #
  # This module will hook into `:net_kernel` to provide dynamic node
  # allocation within a Cachex ring router. There is very minimal
  # support for configuration in here; if you need to see options
  # please visit the parent `Cachex.Router.Ring`.
  #
  # All API in here should be considered private and not relied upon.
  use GenServer
  alias ExHashRing.Ring

  @doc false
  # Initialize the monitor from the options.
  def init(options) do
    # no-op if monitoring is not enabled
    case Keyword.get(options, :monitor) do
      false ->
        :ignore

      true ->
        # pull the ring name and monitor type
        name = Keyword.get(options, :name)
        type = Keyword.get(options, :monitor_type)

        # register to receive node monitoring via :net_kernel
        :ok = :net_kernel.monitor_nodes(true, node_type: type)

        # store name
        {:ok, name}
    end
  end

  @doc false
  # Adds newly detected nodes to the internal ring.
  def handle_info({:nodeup, node, _info}, ring) do
    {:ok, _nodes} = Ring.add_node(ring, node)
    {:noreply, ring}
  end

  @doc false
  # Removes recently dropped nodes from the internal ring.
  def handle_info({:nodedown, node, _info}, ring) do
    {:ok, _nodes} = Ring.remove_node(ring, node)
    {:noreply, ring}
  end
end
