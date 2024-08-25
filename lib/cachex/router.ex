defmodule Cachex.Router do
  @moduledoc """
  Module controlling routing behaviour definitions.

  This module defines the router implementations for Cachex, allowing the user
  to route commands between nodes in a cache cluster. This means that users
  can provide their own routing and rebalancing logic without having to depend
  on it being included in Cachex.
  """

  ##############
  # Public API #
  ##############

  @doc """
  Retrieve all currently connected nodes (including this one).
  """
  @spec connected() :: [atom]
  def connected(),
    do: [node() | :erlang.nodes(:connected)]

  #############
  # Behaviour #
  #############

  @doc """
  Initialize a routing state for a cache.

  Please see all child implementations for supported options.
  """
  @callback init(cache :: Cachex.Spec.cache(), options :: Keyword.t()) :: any

  @doc """
  Retrieve the list of nodes from a routing state.
  """
  @callback nodes(state :: any) :: [atom]

  @doc """
  Route a key to a node in a routing state.
  """
  @callback route(state :: any, key :: any) :: atom

  @doc """
  Create a child specification to back a routing state.
  """
  @callback spec(cache :: Cachex.Spec.cache(), options :: Keyword.t()) ::
              Supervisor.child_spec()

  ##################
  # Implementation #
  ##################

  @doc false
  defmacro __using__(_) do
    quote location: :keep, generated: true do
      @behaviour Cachex.Router

      @doc false
      def init(cache, options \\ []),
        do: nil

      @doc false
      def spec(cache, options),
        do: :ignore

      # state modifiers are overridable
      defoverridable init: 2, spec: 2
    end
  end
end
