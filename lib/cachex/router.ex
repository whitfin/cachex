defmodule Cachex.Router do
  @moduledoc """
  Module controlling routing behaviour definitions.

  This module defines the router implementations for Cachex, allowing the user
  to route commands between nodes in a cache cluster. This means that users
  can provide their own routing and rebalancing logic without having to depend
  on it being included in Cachex.
  """

  #############
  # Behaviour #
  #############

  @doc """
  Initialize a routing state using a list of nodes.
  """
  @callback init(nodes :: [atom], options :: Keyword.t()) :: any

  @doc """
  Retrieve the list of nodes from a routing state.
  """
  @callback nodes(state :: any) :: [atom]

  @doc """
  Route a provided key to a node in a routing state.
  """
  @callback route(state :: any, key :: any) :: atom

  @doc """
  Attach a new node to a routing state.
  """
  @callback attach(state :: any, node :: atom) :: any

  @doc """
  Detach an existing node from a routing state.
  """
  @callback detach(state :: any, node :: atom) :: any

  @doc false
  defmacro __using__(_) do
    quote location: :keep, generated: true do
      # inherit the behaviour
      @behaviour Cachex.Router

      @doc false
      def attach(state, node),
        do:
          raise(RuntimeError,
            message: "Router does not support node addition"
          )

      @doc false
      def detach(state, node),
        do:
          raise(RuntimeError,
            message: "Router does not support node removal"
          )

      # state modifiers are overridable
      defoverridable attach: 2, detach: 2
    end
  end
end
