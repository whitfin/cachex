defmodule Cachex.Connection do
  @moduledoc false
  # Module to handle the connections between remote Cachex nodes and to enforce
  # replication and synchronicity between the nodes. Currently this module is
  # rather small, but has been separated out in anticipation of further work.

  # alias internals
  alias Cachex.Options

  @doc """
  Small module for handling the remote connections and rejoining a Cachex set of
  remote nodes. We go through all supposed connected nodes and ping them to ensure
  they're reachable - we then RPC to one of the online nodes to add the current
  node to Mnesia. This will sync up the nodes and replication, and bring the node
  back into the cluster.
  """
  def ensure_connection(%Options{ cache: cache, nodes: nodes }) do
    case find_online_nodes(nodes) do
      [] -> { :ok, true }
      li -> { :ok, reconnect_node(cache, li) || true }
    end
  end

  # Searches a list of nodes to find those which are online (i.e. those which
  # return :pong when pinged). We filter out the local node name to avoid pinging
  # ourselves unnecessarily.
  defp find_online_nodes(nodes) do
    nodes
    |> Enum.filter(&(is_atom(&1)))
    |> Enum.filter(&(&1 != node()))
    |> Enum.filter(&(:net_adm.ping(&1) == :pong))
  end

  # Loops through a list of nodes and attempts to reconnect to this node from that
  # node. We do it this way as the other nodes can safely replicate to this node
  # before we create our local tables - ensuring consistency.
  defp reconnect_node(cache, nodes) do
    Enum.any?(nodes, fn(remote_node) ->
      :rpc.call(remote_node, Cachex, :add_node, [cache, node()]) == { :ok, true }
    end)
  end

end
