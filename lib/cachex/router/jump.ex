defmodule Cachex.Router.Jump do
  @moduledoc """
  Routing implementation based on Jump Consistent Hash.

  This implementation backed Cachex's distribution in the v3.x lineage, and is
  suitable for clusters of a static size. Each key is hashed and then slotted
  against a node in the cluster. Please note that the hash algorithm should
  not be relied upon and is not considered part of the public API.

  The initialization of this router accepts a `:nodes` option which enables
  the user to define the nodes to route amongst. If this is not provided the
  router will default to detecting a cluster via `Node.self/0` and `Node.list/2`.

  For more information on the algorithm backing this router, please see the
  appropriate [publication](https://arxiv.org/pdf/1406.2294).
  """
  use Cachex.Router
  alias Cachex.Router

  @doc """
  Initialize a jump hash routing state for a cache.

  ## Options

    * `:nodes`

      The `:nodes` option allows a user to provide a list of nodes to treat
      as a cluster. If this is not provided, the cluster will be inferred
      by using `Node.self/1` and `Node.list/2`.

  """
  @spec init(cache :: Cachex.t(), options :: Keyword.t()) :: [atom]
  def init(_cache, options) do
    options
    |> Keyword.get_lazy(:nodes, &Router.connected/0)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Retrieve the list of nodes from a jump hash routing state.
  """
  @spec nodes(nodes :: [atom]) :: [atom]
  def nodes(nodes),
    do: nodes

  @doc """
  Route a key to a node in a jump hash routing state.
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
