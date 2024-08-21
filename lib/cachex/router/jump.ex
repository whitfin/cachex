defmodule Cachex.Router.Jump do
  @moduledoc """
  Basic routing implementation based on Jump Consistent Hash.

  This implementation backed Cachex's distribution in the v3.x lineage,
  and is suitable for clusters of a static size. Attaching and detaching
  nodes after initialization is not supported and will cause an error
  if you attempt to do so.

  For more information on the algorithm backing this router, please
  see the appropriate [publication](https://arxiv.org/pdf/1406.2294).
  """
  use Cachex.Router

  @doc """
  Initialize a routing state using a list of nodes.

  In the case of this router the routing state is simply the list
  of nodes being tracked, with duplicate entries removed.
  """
  @spec init(nodes :: [atom], options :: Keyword.t()) :: [atom]
  def init(nodes, _options),
    do: Enum.uniq(nodes)

  @doc """
  Retrieve the list of nodes from a routing state.
  """
  @spec nodes(nodes :: [atom]) :: [atom]
  def nodes(nodes),
    do: nodes

  @doc """
  Route a provided key to a node in a routing state.
  """
  @spec route(nodes :: [atom], key :: any) :: atom
  def route(nodes, key) do
    slot =
      key
      |> :erlang.phash2()
      |> Jumper.slot(length(nodes))

    Enum.at(nodes, slot)
  end
end
