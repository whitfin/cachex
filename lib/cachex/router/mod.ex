defmodule Cachex.Router.Mod do
  @moduledoc """
  Routing implementation based on basic hashing.

  This router provides the simplest (and quickest!) implementation for
  clusters of a static size. Provided keys are hashed and routed to a node
  via the modulo operation. Please note that the hash algorithm should
  not be relied upon and is not considered part of the public API.

  The initialization of this router accepts a `:nodes` option which enables
  the user to define the nodes to route amongst. If this is not provided the
  router will default to detecting a cluster via `Node.self/0` and `Node.list/1`.
  """
  use Cachex.Router
  alias Cachex.Router

  @doc """
  Initialize a modulo routing state for a cache.

  ## Options

    * `:nodes`

      The `:nodes` option allows a user to provide a list of nodes to treat
      as a cluster. If this is not provided, the cluster will be inferred
      by using `Node.self/0` and `Node.list/1`.

  """
  @spec init(cache :: Cachex.t(), options :: Keyword.t()) :: [atom]
  def init(_cache, options) do
    options
    |> Keyword.get_lazy(:nodes, &Router.connected/0)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Retrieve the list of nodes from a modulo routing state.
  """
  @spec nodes(nodes :: [atom]) :: [atom]
  def nodes(nodes),
    do: Enum.sort(nodes)

  @doc """
  Route a key to a node in a modulo routing state.
  """
  @spec route(nodes :: [atom], key :: any) :: atom
  def route(nodes, key) do
    slot =
      key
      |> :erlang.phash2()
      |> rem(length(nodes))

    Enum.at(nodes, slot)
  end
end
