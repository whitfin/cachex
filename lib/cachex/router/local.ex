defmodule Cachex.Router.Local do
  @moduledoc """
  Routing implementation for the local node.

  This module acts as the base implementation for routing when *not* being
  used in a distributed cache. All actions are routed to the current node.
  """
  use Cachex.Router

  @doc """
  Retrieve the list of nodes from a local routing state.
  """
  @spec nodes(state :: nil) :: [atom()]
  def nodes(_state),
    do: [node()]

  @doc """
  Route a key to a node in a local routing state.
  """
  @spec route(state :: nil, key :: any()) :: atom()
  def route(_state, _key),
    do: node()
end
