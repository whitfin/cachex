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
  @spec new(nodes :: [atom], options :: Keyword.t()) :: HashRing.t()
  def new(nodes, _options \\ []) do
    ring = HashRing.new()
    ring = HashRing.add_nodes(ring, nodes)
    ring
  end

  @doc """
  Retrieve the list of nodes from a ring.
  """
  @spec nodes(ring :: HashRing.t()) :: [atom]
  def nodes(ring) do
    ring
    |> HashRing.nodes()
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Route a provided key to a node in a ring.
  """
  @spec route(ring :: HashRing.t(), key :: any) :: atom
  def route(ring, key),
    do: HashRing.key_to_node(ring, key)

  @doc """
  Attach a new node to a ring.
  """
  @spec attach(ring :: HashRing.t(), node :: atom) :: HashRing.t()
  def attach(ring, node),
    do: HashRing.add_node(ring, node)

  @doc """
  Detach an existing node to a ring.
  """
  @spec detach(ring :: HashRing.t(), node :: atom) :: HashRing.t()
  def detach(ring, node),
    do: HashRing.remove_node(ring, node)
end
