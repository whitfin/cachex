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

  ####################
  # Server Callbacks #
  ####################

  @doc false
  # Initialize the monitor from the options.
  def init(options) do
    case Keyword.get(options, :monitor) do
      false ->
        :ignore

      true ->
        name = Keyword.get(options, :name)
        type = Keyword.get(options, :monitor_type)

        includes = Keyword.get(options, :monitor_includes, [])
        excludes = Keyword.get(options, :monitor_includes, [])

        :ok = :net_kernel.monitor_nodes(true, node_type: type)

        {:ok, {name, {includes, excludes}}}
    end
  end

  @doc false
  # Adds newly detected nodes to the internal ring, if they match any
  # of the # provided monitoring patterns inside the options listing.
  def handle_info({:nodeup, node, _info}, {ring, {includes, excludes}} = state) do
    if Cachex.Router.Ring.included?(node, includes, excludes) do
      Ring.add_node(ring, node)
    end

    {:noreply, state}
  end

  @doc false
  # Removes recently dropped nodes from the internal ring, regardless of
  # whether it already exists in the ring or not for consistency.
  def handle_info({:nodedown, node, _info}, {ring, _patterns} = state) do
    Ring.remove_node(ring, node)
    {:noreply, state}
  end
end
