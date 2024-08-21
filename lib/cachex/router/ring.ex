defmodule Cachex.Router.Ring do
  @moduledoc """
  Simple routing implementation based on a consistent hash ring.

  This implementation makes use of a hashing ring to better enable
  modification of the internal node listing. Cachex uses the library
  [libring](https://github.com/bitwalker/libring) to do the heavy
  lifting here.
  """
  use Cachex.Router

  @doc """
  Initialize a ring using a list of nodes.
  """
  def init(nodes, _options \\ []) do
    ring = HashRing.new()
    ring = HashRing.add_nodes(ring, nodes)
    ring
  end

  @doc """
  Retrieve the list of nodes from a ring.
  """
  defdelegate nodes(ring), to: HashRing, as: :nodes

  @doc """
  Route a provided key to a node in a ring.
  """
  defdelegate route(ring, key), to: HashRing, as: :key_to_node

  @doc """
  Attach a new node to a ring.
  """
  defdelegate attach(ring, node), to: HashRing, as: :add_node

  @doc """
  Detach an existing node to a ring.
  """
  defdelegate detach(ring, node), to: HashRing, as: :remove_node
end
